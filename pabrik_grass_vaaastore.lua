local SC = "AUTO PABRIK GRASS VaaaStore v1.2"
local C = {
    plant_count   = 20,
    plant_offset  = 2,
    seed_name     = "Grass Seed",
    block_name    = "Grass",
    vend_name     = "Vending Machine",
    seed_id = nil, block_id = nil, vend_id = nil,
    stack_cap     = 200,
    manual_wait   = 60000,
    max_hits      = 12,
    delay_min     = 180,
    delay_max     = 300,
    grow_time_ms  = 68000,
    pnb_offsets   = {-1, 0, 1},
    dump_vend     = "vending_dump.txt"
}

local function log_hp(t) log("[" .. SC .. "] " .. tostring(t)) end
local RUN, ID, home, V = true, {}, {x = 0, y = 0}, {wait = false, dialog = nil, learning = false, rec = {}, dlgs = {}}
local stats, start_world = {cycles = 0, planted = 0, stocked = 0, setor_count = 0}, ""
local current_vend_idx = 1
local pref

do
    local ok, p = pcall(function()
        local m = require("preferences")
        m:new("pabrik_grass_vaaastore_v2")
        return m
    end)
    if ok then
        pref = p
        pcall(function() pref:load() end)
    end
end

local function pget(k, d)
    if not pref then return d end
    local ok, v = pcall(function() return pref:get(k, d) end)
    if ok and v ~= nil then return v end
    return d
end

local function pset(k, v)
    if pref then pcall(function() pref:set(k, v) pref:save() end) end
end

local lag = 0
local function pause(lo, hi) sleep(math.random(lo or C.delay_min, hi or C.delay_max) + lag) end
local function lag_bad() lag = math.min(lag + 200, 1500) end
local function lag_ok() lag = math.max(lag - 50, 0) end

local function wait_until(fn, ms)
    local t = getTime()
    while getTime() - t < ms do
        local ok, r = pcall(fn)
        if ok and r then return true end
        sleep(50)
    end
    return false
end

local function inv(id)
    for _, it in pairs(getInventory()) do
        if it.id == id then return it.amount end
    end
    return 0
end

local function tile(x, y)
    local ok, t = pcall(getTile, x, y)
    if ok then return t end
end

local function tile_pos()
    local me = getLocal()
    return me.posX // 32, me.posY // 32
end

local function world_name()
    local ok, w = pcall(getCurrentWorldName)
    return (ok and w) or ""
end

local function ready()
    local ok, me = pcall(getLocal)
    return ok and me ~= nil and me.posX ~= nil and world_name() ~= ""
end

local function resolve(name, manual)
    if manual then return manual end
    local ok, id = pcall(findItemID, name)
    if ok and type(id) == "number" and id > 0 then return id end
    local ok2, info = pcall(getItemInfoByName, name)
    if ok2 and info and info.id and info.id > 0 then return info.id end
end

local function walk_to(x, y)
    local px, py = tile_pos()
    if px == x and py == y then return true end
    FindPath(x, y)
    local t = getTime()
    while getTime() - t < 3000 do
        px, py = tile_pos()
        if px == x and py == y then return true end
        sleep(100)
    end
    return false
end

local function act(x, y, item)
    local me = getLocal()
    sendPacketRaw(false, {type = 3, value = item, px = x, py = y, x = me.posX, y = me.posY})
end

local function obj_tile(o) return o.pos.x // 32, o.pos.y // 32 end

local function collect()
    local px, py = tile_pos()
    for _, o in pairs(getObjectList()) do
        local ox, oy = obj_tile(o)
        if math.abs(ox - px) <= 3 and math.abs(oy - py) <= 3 then
            sendPacketRaw(false, {type = 11, value = o.id, x = o.pos.x, y = o.pos.y})
        end
    end
end

local function floor_total(item)
    local n = 0
    for _, o in pairs(getObjectList()) do
        if o.itemid == item then n = n + o.amount end
    end
    return n
end

local function fetch_floor(item)
    for _, o in pairs(getObjectList()) do
        if o.itemid == item then
            if inv(item) >= C.stack_cap then return end
            local ox, oy = obj_tile(o)
            if walk_to(ox, oy) then
                collect()
                pause()
            end
        end
    end
end

local function banner(title, lines)
    local d = {
        "set_default_color|`o",
        "add_label_with_icon|big|`w" .. title .. "``|left|" .. (ID.seed or 242) .. "|",
        "add_spacer|small|"
    }
    for _, l in ipairs(lines) do d[#d + 1] = "add_smalltext|" .. l .. "``|left|" end
    d[#d + 1] = "add_spacer|small|"
    d[#d + 1] = "end_dialog|pabrik_grass_vaaastore|Close|OKE|"
    pcall(growtopia.sendDialog, table.concat(d, "\n"))
end

local function banner_start()
    banner(SC, {
        "`2VaaaStore - Pabrik rumput otomatis v2.0",
        "`oAlur: Plant > Fast Harvest Ready > Fast 3-Tile PNB > Sweep > Restock 190 Seed.",
        "`oPosisi awal: " .. home.x .. "," .. home.y,
        "`oSetor Vending: setelah plant, saat seed di tas >= " .. (C.stack_cap - C.plant_count) .. " (seluruh seed di tas disetor).",
        "`9Mencari Vending baru secara otomatis jika yang sekarang sudah penuh."
    })
end

local function banner_stop(reason)
    banner(SC .. " - SELESAI", {
        "`4Script berhenti: " .. reason,
        "`oSiklus selesai: " .. stats.cycles,
        "`oTanaman ditanam: " .. stats.planted,
        "`oTotal Setor Vending: " .. stats.stocked .. " seed (" .. stats.setor_count .. "x setor)",
        "`2Terima kasih sudah memakai VaaaStore."
    })
end

local function shutdown(reason)
    if not RUN then return end
    RUN = false
    log_hp("BERHENTI: " .. reason)
    banner_stop(reason)
    pcall(removeHook, "onVariant")
    pcall(removeHook, "onSendPacket")
end

local function plant_tile(x, y)
    act(x, y, ID.seed)
    pause()
    local ok = wait_until(function()
        local g = tile(x, y)
        return g and g.fg == ID.seed
    end, 1000)
    if ok then lag_ok() return true end
    lag_bad()
    return false
end

local function plant_phase()
    log_hp("Planting...")
    local list = {}
    for i = 0, C.plant_count - 1 do
        local x, y = home.x + C.plant_offset + i, home.y
        local t, b = tile(x, y), tile(x, y + 1)
        if not t or not b or b.fg == 0 then break end
        if t.fg == ID.seed then
            list[#list + 1] = {x = x, y = y}
        elseif t.fg == 0 then
            if inv(ID.seed) <= 0 then break end
            if walk_to(x, y) and plant_tile(x, y) then
                list[#list + 1] = {x = x, y = y}
                stats.planted = stats.planted + 1
            else
                break
            end
        else
            break
        end
    end
    log_hp("Plant selesai: " .. #list .. " tile")
    return list
end

local function harvest_as_ready(list)
    log_hp("Menunggu & Panen Instan (Ready First)...")
    local total, done, finished = #list, 0, {}
    local start_time = getTime()
    while done < total and RUN do
        for i, p in ipairs(list) do
            if not finished[i] then
                local t = tile(p.x, p.y)
                if not t or t.fg ~= ID.seed then
                    finished[i] = true
                    done = done + 1
                elseif t.readyharvest and walk_to(p.x, p.y) then
                    act(p.x, p.y, 18)
                    pause()
                    collect()
                    local cleared = wait_until(function()
                        local g = tile(p.x, p.y)
                        return g and (g.fg ~= ID.seed or not g.readyharvest)
                    end, 800)
                    if cleared then
                        lag_ok()
                        finished[i] = true
                        done = done + 1
                    else
                        lag_bad()
                    end
                end
            end
        end
        if done >= total then break end
        if getTime() - start_time > (C.grow_time_ms + 15000 + total * 1500) then
            log_hp("Timeout menunggu tanaman panen.")
            break
        end
        sleep(200)
    end
    log_hp("Harvest selesai: " .. done .. "/" .. total)
end

local function fast_pnb_3tiles()
    if inv(ID.block) <= 0 then return end
    walk_to(home.x, home.y)
    
    local placed = {}
    for _, dx in ipairs(C.pnb_offsets) do
        local tx, ty = home.x + dx, home.y - 1
        local t = tile(tx, ty)
        if t and t.fg == 0 and inv(ID.block) > 0 then
            act(tx, ty, ID.block)
            placed[#placed + 1] = {x = tx, y = ty}
            pause(80, 120)
        end
    end
    wait_until(function()
        for _, p in ipairs(placed) do
            local g = tile(p.x, p.y)
            if not g or g.fg ~= ID.block then return false end
        end
        return true
    end, 800)

    local hits = 0
    while hits < C.max_hits and RUN do
        local all_clear = true
        for _, dx in ipairs(C.pnb_offsets) do
            local tx, ty = home.x + dx, home.y - 1
            local t = tile(tx, ty)
            if t and t.fg == ID.block then
                all_clear = false
                act(tx, ty, 18)
            end
        end
        collect()
        pause(120, 180)
        hits = hits + 1
        if all_clear then break end
    end
end

local function pnb()
    log_hp("Fast PNB (3-Tile Batch)...")
    local last_remain, idle = nil, 0
    while RUN do
        local remain = inv(ID.block) + floor_total(ID.block)
        if remain == 0 then
            log_hp("PNB Selesai, block bersih.")
            return true
        end
        
        if last_remain and remain >= last_remain then idle = idle + 1 else idle = 0 end
        if idle >= 15 then
            log_hp("PNB macet, sisa block: " .. remain)
            return false
        end
        last_remain = remain
        
        if inv(ID.block) <= 0 then fetch_floor(ID.block) end
        if inv(ID.block) > 0 then
            fast_pnb_3tiles()
        end
    end
    return false
end

local function sweep()
    log_hp("Sweeping ceceran...")
    for _ = 1, 5 do
        fetch_floor(ID.block)
        fetch_floor(ID.seed)
        if inv(ID.block) > 0 then pnb() end
        local block_left = inv(ID.block) + floor_total(ID.block)
        local seed_left = floor_total(ID.seed)
        if block_left == 0 and (seed_left == 0 or inv(ID.seed) >= C.stack_cap) then break end
    end
    walk_to(home.x, home.y)
end

local function wrench(x, y)
    local me = getLocal()
    sendPacketRaw(false, {type = 3, value = 32, px = x, py = y, x = me.posX, y = me.posY})
end

local function get_all_vendings()
    local list = {}
    for _, t in pairs(getTiles()) do
        if t.fg == ID.vend then
            local d = math.abs(t.x - home.x) + math.abs(t.y - home.y)
            list[#list + 1] = {x = t.x, y = t.y, dist = d}
        end
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    return list
end

local function stand_near(vx, vy)
    local px, py = tile_pos()
    if math.abs(px - vx) <= 2 and math.abs(py - vy) <= 2 then return true end
    for _, d in ipairs({{-1, 0}, {1, 0}, {-2, 0}, {2, 0}, {0, -1}}) do
        local x, y = vx + d[1], vy + d[2]
        local t = tile(x, y)
        if t and t.fg == 0 and walk_to(x, y) then return true end
    end
    return false
end

local function save_tpl(list)
    local enc = {}
    for _, s in ipairs(list) do enc[#enc + 1] = (s:gsub("\n", "~N~")) end
    pset("vend_tpl", table.concat(enc, "@@"))
end

local function load_tpl()
    local s = pget("vend_tpl", "")
    if s == "" then return nil end
    local out = {}
    for part in (s .. "@@"):gmatch("(.-)@@") do
        if part ~= "" then out[#out + 1] = (part:gsub("~N~", "\n")) end
    end
    if #out > 0 then return out end
end

local function build_tpl(rec, vx, vy, item)
    local out = {}
    for _, pkt in ipairs(rec) do
        if pkt:find("tilex|", 1, true) or pkt:lower():find("vend", 1, true) then
            local p = pkt
            p = p:gsub("tilex|" .. vx .. "%f[%D]", "tilex|{X}")
            p = p:gsub("tiley|" .. vy .. "%f[%D]", "tiley|{Y}")
            p = p:gsub("|" .. item .. "%f[%D]", "|{ITEM}")
            out[#out + 1] = p
        end
    end
    return out
end

local function replay(tpl, vx, vy, before)
    V.wait, V.dialog = true, nil
    wrench(vx, vy)
    if not wait_until(function() return V.dialog ~= nil end, 5000) then
        V.wait = false
        return false
    end
    for _, step in ipairs(tpl) do
        local pkt = step
        pkt = pkt:gsub("{X}", tostring(vx))
        pkt = pkt:gsub("{Y}", tostring(vy))
        pkt = pkt:gsub("{ITEM}", tostring(ID.seed))
        sendPacket(2, pkt)
        pause(500, 900)
    end
    V.wait = false
    return wait_until(function() return inv(ID.seed) < before end, 5000)
end

local function manual_restock(vx, vy, before)
    V.learning, V.rec, V.dlgs = true, {}, {}
    growtopia.notify("`2Setor seluruh seed ke Vending secara manual (script merekam paket)...")
    log_hp("MODE BELAJAR: Masukkan seed ke Vending secara manual...")
    local ok = wait_until(function() return inv(ID.seed) < before end, C.manual_wait)
    V.learning = false
    if not ok then return false end
    local tpl = build_tpl(V.rec, vx, vy, ID.seed)
    if #tpl > 0 then
        save_tpl(tpl)
        log_hp("Template restock tersimpan (" .. #tpl .. " langkah).")
    end
    return true
end

local function restock()
    local vends = get_all_vendings()
    if #vends == 0 then return false, "Tidak ada Vending Machine ditemukan" end
    local tpl = load_tpl()
    local had_tpl = tpl ~= nil

    while current_vend_idx <= #vends do
        local v = vends[current_vend_idx]
        log_hp("Mencoba setor ke Vending #" .. current_vend_idx .. " di (" .. v.x .. "," .. v.y .. ")")
        local ok = false
        if not stand_near(v.x, v.y) then
            log_hp("Gagal mendekati Vending #" .. current_vend_idx)
        else
            local before = inv(ID.seed)
            if tpl then ok = replay(tpl, v.x, v.y, before) else ok = manual_restock(v.x, v.y, before) end
            if ok then
                local delta = before - inv(ID.seed)
                stats.stocked = stats.stocked + delta
                stats.setor_count = stats.setor_count + 1
                if tpl then pset("vend_tpl_ok", 1) elseif load_tpl() then pset("vend_tpl_ok", 1) end
                log_hp("Sukses setor " .. delta .. " seed ke Vending #" .. current_vend_idx)
                walk_to(home.x, home.y)
                return true
            end
            log_hp("Vending #" .. current_vend_idx .. " penuh/gagal")
        end
        current_vend_idx = current_vend_idx + 1
    end

    if had_tpl and pget("vend_tpl_ok", 0) ~= 1 then pset("vend_tpl", "") end
    return false, "Semua Vending Machine di world sudah penuh/tidak bisa diakses"
end

local function on_variant(var)
    local ok, res = pcall(function()
        if var.v1 ~= "OnDialogRequest" or type(var.v2) ~= "string" then return false end
        if V.wait then
            V.dialog = var.v2
            pcall(writeToLocal, C.dump_vend, var.v2)
            return true
        end
        if V.learning then
            V.dlgs[#V.dlgs + 1] = var.v2
            pcall(writeToLocal, C.dump_vend, table.concat(V.dlgs, "\n-----\n"))
        end
        return false
    end)
    return ok and res or false
end

local function on_send(ptype, pkt)
    pcall(function()
        if V.learning and type(pkt) == "string" and pkt:find("action|dialog_return", 1, true) then
            V.rec[#V.rec + 1] = pkt
        end
    end)
    return false
end

local function guarded(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        log_hp("Error: " .. tostring(err))
        sleep(2000)
    end
    return ok
end

local function same_world() return world_name():upper() == start_world:upper() end

local function main()
    if not wait_until(ready, 30000) then log_hp("Belum masuk world") return end
    start_world = world_name()
    ID.seed = resolve(C.seed_name, C.seed_id)
    ID.block = resolve(C.block_name, C.block_id)
    ID.vend = resolve(C.vend_name, C.vend_id)

    log_hp("ID terdeteksi: seed=" .. tostring(ID.seed) .. " block=" .. tostring(ID.block) .. " vend=" .. tostring(ID.vend))
    if not ID.seed or not ID.block then
        shutdown("ID item tidak ditemukan")
        return
    end

    home.x, home.y = tile_pos()
    banner_start()
    log_hp("Script dimulai di " .. start_world .. " (" .. home.x .. "," .. home.y .. ")")

    while RUN do
        if not same_world() then shutdown("keluar dari world " .. start_world) break end
        if inv(ID.seed) <= 0 then fetch_floor(ID.seed) end
        if inv(ID.seed) <= 0 then shutdown("seed di tas habis") break end

        local list = {}
        guarded(function() list = plant_phase() end)
        if #list == 0 then shutdown("tidak ada tile tanam valid") break end

        local limit = C.stack_cap - C.plant_count
        if inv(ID.seed) >= limit then
            log_hp("Seed di tas " .. inv(ID.seed) .. " (>= " .. limit .. ") setelah plant, setor Vending...")
            local ok, why = false, ""
            guarded(function() ok, why = restock() end)
            if not ok then
                shutdown(why ~= "" and why or "Gagal setor ke semua Vending Machine")
                break
            end
        end

        guarded(function()
            harvest_as_ready(list)
            walk_to(home.x, home.y)
            pnb()
            sweep()
        end)

        stats.cycles = stats.cycles + 1
        log_hp("Siklus " .. stats.cycles .. " selesai. Seed di tas: " .. inv(ID.seed))
        pause(500, 1000)
    end
end

addHook(on_variant, "onVariant")
addHook(on_send, "onSendPacket")
applyHook()
log_hp("dimuat")
runThread(main)
