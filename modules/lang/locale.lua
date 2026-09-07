-- locale.lua
--- 旅人辞典自带 locale：三语注册 + fallback，无 __index，取值必须走 L("key")。
--- 提供 :Get(key, ...) 与 __call；没有 __index，取值必须走 L("key")。

local L = {}
_G.TJ_L = L

L.defaultLocale = "zhCN"
L.supportedLocales = {
    zhCN = true,
    zhTW = true,
    enUS = true,
}

local clientLocale = string.lower(tostring(GetLocale() or L.defaultLocale))
L.clientLocale = clientLocale

if clientLocale == "engb" then
    clientLocale = "enus"
    L.clientLocale = clientLocale
end

if L.supportedLocales[clientLocale] and rawget(L, clientLocale) then
    L.activeLocale = clientLocale
else
    L.activeLocale = L.defaultLocale
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

setmetatable(L, {
    __call = function(self, key, ...)
        return self:Get(key, ...)
    end,
})
