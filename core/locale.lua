-- core/locale.lua
local _, TJ = ...

TJ.L = TJ.L or {}
local L = TJ.L
_G.TJ_L = L

L.defaultLocale = "zhCN"
L.supportedLocales = {
    zhCN = true,
    zhTW = true,
    enUS = true,
}

local clientLocale = string.lower(tostring(GetLocale() or L.defaultLocale))
L.clientLocale = clientLocale

-- British English clients use the same enUS strings.
if clientLocale == "engb" then
    clientLocale = "enus"
    L.clientLocale = clientLocale
end

if L.supportedLocales[clientLocale] and rawget(L, clientLocale) then
    L.activeLocale = clientLocale
else
    L.activeLocale = L.defaultLocale
end

local function NormalizeLocale(locale)
    locale = string.lower(tostring(locale or ""))
    locale = string.gsub(locale, "^%s+", "")
    locale = string.gsub(locale, "%s+$", "")
    return locale
end

function L:NormalizeLocale(locale)
    return NormalizeLocale(locale)
end

function L:RegisterLocale(locale, strings)
    locale = NormalizeLocale(locale)
    if locale == "" or type(strings) ~= "table" then
        return false
    end

    rawset(self, locale, strings)
    if locale == self.clientLocale then
        self.activeLocale = locale
    end
    return true
end

function L:GetClientLocale()
    return self.clientLocale
end

function L:GetActiveLocale()
    return self.activeLocale
end

function L:GetDefaultLocale()
    return self.defaultLocale
end

function L:Get(key, ...)
    local active = rawget(self, self.activeLocale)
    local fallback = rawget(self, self.defaultLocale)
    local value = active and active[key] or nil
    if value == nil then
        value = fallback and fallback[key] or nil
    end
    if value == nil then
        return tostring(key)
    end

    if select("#", ...) > 0 and type(value) == "string" then
        return string.format(value, ...)
    end
    return value
end

function L:Exists(key)
    local active = rawget(self, self.activeLocale)
    local fallback = rawget(self, self.defaultLocale)
    return (active and active[key] ~= nil)
        or (fallback and fallback[key] ~= nil)
        or false
end

setmetatable(L, {
    __call = function(self, key, ...)
        return self:Get(key, ...)
    end,
})
