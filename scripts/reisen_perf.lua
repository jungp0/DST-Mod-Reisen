--[[
reisen_perf — Lightweight in-game performance probe
==============================================================================

A single switch turns on:
  - Counters       (call frequency)
  - Time aggregates (total / max / avg ms in a 5 s window)
  - Spike detection (logs when a single call exceeds threshold)
  - Periodic dump to log (or a single capture on demand)

Cost when disabled: a single boolean read per Track / Time call site.
Public API:
  Perf.IsEnabled()                 -> bool
  Perf.SetEnabled(b)               -- toggle on / off (also re-arms the dump task)
  Perf.Bump(name, n)               -- increment counter (default n = 1)
  Perf.AddTime(name, ms)           -- add a sample to a duration aggregate
  Perf.Time(name, fn, ...)         -- run fn(...) and add elapsed ms; returns fn's results
  Perf.Begin(name)                 -- returns a closure; call it to End() and add elapsed ms
  Perf.BeginWarn(name, threshold)  -- like Begin but logs if elapsed > threshold ms
  Perf.Dump()                      -- print + reset the current window now (server only)
  Perf.SetSpikeThreshold(ms)       -- set global spike threshold (default 16ms ~= 1 frame)

Console usage from in-game console (default key: ` then ~):
  ReisenPerf(true)                 -- enable, arms the periodic dump
  ReisenPerf(false)                -- disable, cancels the periodic dump
  ReisenPerf("dump")               -- print current window without resetting period
  ReisenPerf("spike", 8)           -- set spike threshold to 8ms
==============================================================================
--]]

local Perf = {}

local _enabled       = false
local _counters      = {}    -- name -> count
local _times_total   = {}    -- name -> total ms in window
local _times_max     = {}    -- name -> max single-sample ms in window
local _times_count   = {}    -- name -> sample count
local _spikes        = {}    -- name -> spike count (samples > threshold)
local _window_start  = 0
local _dump_task     = nil

local DUMP_INTERVAL      = 5.0    -- seconds; matches typical server tick budget
local SPIKE_THRESHOLD_MS = 16.0   -- ~1 frame at 60fps; log when exceeded

local function _now_ms()
    -- GetTimeReal is wall-clock ms; use it on both client and server
    local fn = _G.GetTimeReal
    if fn ~= nil then
        return fn()
    end
    return (os.clock() * 1000.0)
end

local function _reset_window()
    for k in pairs(_counters)    do _counters[k]    = 0 end
    for k in pairs(_times_total) do _times_total[k] = 0 end
    for k in pairs(_times_max)   do _times_max[k]   = 0 end
    for k in pairs(_times_count) do _times_count[k] = 0 end
    for k in pairs(_spikes)      do _spikes[k]      = 0 end
    _window_start = _now_ms()
end

function Perf.SetSpikeThreshold(ms)
    SPIKE_THRESHOLD_MS = ms or 16.0
    print(string.format("[REISEN_PERF] spike threshold set to %.2fms", SPIKE_THRESHOLD_MS))
end

function Perf.IsEnabled()
    return _enabled
end

function Perf.Bump(name, n)
    if not _enabled then return end
    _counters[name] = (_counters[name] or 0) + (n or 1)
end

function Perf.AddTime(name, ms, warn_threshold)
    if not _enabled then return end
    _times_total[name] = (_times_total[name] or 0) + ms
    if (_times_max[name] or 0) < ms then
        _times_max[name] = ms
    end
    _times_count[name] = (_times_count[name] or 0) + 1
    local thresh = warn_threshold or SPIKE_THRESHOLD_MS
    if ms > thresh then
        _spikes[name] = (_spikes[name] or 0) + 1
        print(string.format("[REISEN_PERF] SPIKE %s: %.2fms (threshold %.2fms)", name, ms, thresh))
    end
end

function Perf.Time(name, fn, ...)
    if not _enabled then
        return fn(...)
    end
    local t0 = _now_ms()
    local a, b, c, d = fn(...)
    Perf.AddTime(name, _now_ms() - t0)
    return a, b, c, d
end

-- Begin/End style for code paths that don't fit a single fn(...) form.
local _NOOP = function() end  -- constant empty closure to avoid per-call allocation
function Perf.Begin(name)
    if not _enabled then
        return _NOOP
    end
    local t0 = _now_ms()
    return function()
        Perf.AddTime(name, _now_ms() - t0)
    end
end

function Perf.BeginWarn(name, threshold)
    if not _enabled then
        return _NOOP
    end
    local t0 = _now_ms()
    local thresh = threshold or SPIKE_THRESHOLD_MS
    return function()
        Perf.AddTime(name, _now_ms() - t0, thresh)
    end
end

local function _sorted_keys(tbl)
    local keys = {}
    for k in pairs(tbl) do table.insert(keys, k) end
    table.sort(keys)
    return keys
end

function Perf.Dump()
    local span_ms = _now_ms() - _window_start
    if span_ms <= 0 then span_ms = 1 end
    local span_s = span_ms / 1000.0
    print(string.format("[REISEN_PERF] ===== window=%.2fs (spike_thresh=%.1fms) =====", span_s, SPIKE_THRESHOLD_MS))

    local cnt_keys = _sorted_keys(_counters)
    if #cnt_keys > 0 then
        print("[REISEN_PERF] counters (calls/s):")
        for _, k in ipairs(cnt_keys) do
            local v = _counters[k]
            if v ~= 0 then
                print(string.format("[REISEN_PERF]   %-40s  %6d  (%.2f/s)", k, v, v / span_s))
            end
        end
    end

    local tm_keys = _sorted_keys(_times_total)
    if #tm_keys > 0 then
        print("[REISEN_PERF] times (total / max / avg ms, calls, spikes):")
        for _, k in ipairs(tm_keys) do
            local total = _times_total[k] or 0
            local n     = _times_count[k] or 0
            if n > 0 then
                local mx     = _times_max[k] or 0
                local avg    = total / n
                local spikes = _spikes[k] or 0
                local spike_str = spikes > 0 and string.format("  SPIKES=%d", spikes) or ""
                print(string.format("[REISEN_PERF]   %-40s  total=%7.2f  max=%6.2f  avg=%5.3f  n=%d%s",
                    k, total, mx, avg, n, spike_str))
            end
        end
    end

    local total_spikes = 0
    for _, v in pairs(_spikes) do total_spikes = total_spikes + v end
    if total_spikes > 0 then
        print(string.format("[REISEN_PERF] TOTAL SPIKES in window: %d", total_spikes))
    end
end

local function _arm_dump_task()
    if _dump_task ~= nil then
        _dump_task:Cancel()
        _dump_task = nil
    end
    if not _enabled then return end
    local TheWorld = _G.TheWorld
    if TheWorld == nil then
        -- World not ready yet (e.g. perf toggled from main menu).  The user is
        -- expected to enable perf after entering a world, so just print a hint.
        print("[REISEN_PERF] note: world not ready; periodic dump will not start until you re-toggle ReisenPerf(true) in-game")
        return
    end
    _dump_task = TheWorld:DoPeriodicTask(DUMP_INTERVAL, function()
        if not _enabled then return end
        Perf.Dump()
        _reset_window()
    end)
end

function Perf.SetEnabled(b)
    b = b and true or false
    if b == _enabled then return end
    _enabled = b
    _reset_window()
    _arm_dump_task()
    print(string.format("[REISEN_PERF] %s", _enabled and "ENABLED" or "DISABLED"))
end

-- Console-callable entry; accepts true / false / "dump" / "spike".
function Perf.Console(arg, arg2)
    if arg == "dump" or arg == "DUMP" then
        Perf.Dump()
        _reset_window()
        return
    end
    if arg == "spike" or arg == "SPIKE" then
        Perf.SetSpikeThreshold(arg2)
        return
    end
    Perf.SetEnabled(arg)
end

return Perf
