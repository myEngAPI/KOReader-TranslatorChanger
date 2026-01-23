--[[--
DeepL Translation Plugin for KOReader

This module provides DeepL translation engine as an alternative to Google Translate.
It uses the DeepL API to translate text with better quality for users in China.

DeepL API Documentation:
- Free API: https://api-free.deepl.com/v2/translate
- Pro API: https://api.deepl.com/v2/translate
- Get API key: https://www.deepl.com/pro-api

@module koplugin.DeepLTranslator
--]]

local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local JSON = require("json")
local Screen = require("device").screen
local ffiUtil = require("ffi/util")
local logger = require("logger")
local util = require("util")
local T = ffiUtil.template
local _ = require("gettext")

local AUTODETECT_LANGUAGE = ""

local SUPPORTED_LANGUAGES = {
    BG = _("保加利亚语"),
    CS = _("捷克语"),
    DA = _("丹麦语"),
    DE = _("德语"),
    EL = _("希腊语"),
    ["EN-GB"] = _("英语（英式）"),
    ["EN-US"] = _("英语（美式）"),
    ES = _("西班牙语"),
    ET = _("爱沙尼亚语"),
    FI = _("芬兰语"),
    FR = _("法语"),
    HU = _("匈牙利语"),
    ID = _("印尼语"),
    IT = _("意大利语"),
    JA = _("日语"),
    KO = _("韩语"),
    LT = _("立陶宛语"),
    LV = _("拉脱维亚语"),
    NB = _("挪威语（书面语）"),
    NL = _("荷兰语"),
    PL = _("波兰语"),
    ["PT-BR"] = _("葡萄牙语（巴西）"),
    ["PT-PT"] = _("葡萄牙语（欧洲）"),
    RO = _("罗马尼亚语"),
    RU = _("俄语"),
    SK = _("斯洛伐克语"),
    SL = _("斯洛文尼亚语"),
    SV = _("瑞典语"),
    TR = _("土耳其语"),
    UK = _("乌克兰语"),
    ZH = _("中文（简体）"),
}

local ALT_LANGUAGE_CODES = {
    ["zh-CN"] = "ZH",
    ["zh-TW"] = "ZH",
    en = "EN-US",
}

local DeepLTranslator = {
    api_servers = {
        free = "https://api-free.deepl.com",
        pro = "https://api.deepl.com",
    },
    api_path = "/v2/translate",
    api_key = nil,
    api_type = "free",
    default_lang = "ZH",
}

function DeepLTranslator:getApiServer()
    local api_type = G_reader_settings:readSetting("deepl_api_type") or self.api_type
    return self.api_servers[api_type] or self.api_servers.free
end

function DeepLTranslator:getApiKey()
    local api_key = G_reader_settings:readSetting("deepl_api_key")
    if not api_key or api_key == "" then
        return nil
    end
    return api_key
end

function DeepLTranslator:getLanguageName(lang, default_string)
    if SUPPORTED_LANGUAGES[lang] then
        return SUPPORTED_LANGUAGES[lang], true
    elseif ALT_LANGUAGE_CODES[lang] then
        return SUPPORTED_LANGUAGES[ALT_LANGUAGE_CODES[lang]], true
    elseif lang then
        return lang:upper(), false
    end
    return default_string, false
end

function DeepLTranslator:genSettingsMenu()
    local function genLanguagesItems(setting_name, default_checked_item)
        local items_table = {}
        for lang_key, lang_name in ffiUtil.orderedPairs(SUPPORTED_LANGUAGES) do
            table.insert(items_table, {
                text_func = function()
                    return T("%1 (%2)", lang_name, lang_key)
                end,
                checked_func = function()
                    return lang_key == (G_reader_settings:readSetting(setting_name) or default_checked_item)
                end,
                radio = true,
                callback = function()
                    G_reader_settings:saveSetting(setting_name, lang_key)
                end,
            })
        end
        return items_table
    end

    return {
        text = _("DeepL设置"),
        sub_item_table = {
            {
                text = _("API密钥"),
                help_text = _([[输入您的DeepL API密钥。获取免费API密钥：https://www.deepl.com/pro-api]]),
                keep_menu_open = true,
                callback = function()
                    local InputDialog = require("ui/widget/inputdialog")
                    local api_key_input
                    api_key_input = InputDialog:new{
                        title = _("DeepL API密钥"),
                        input = G_reader_settings:readSetting("deepl_api_key") or "",
                        input_hint = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
                        input_type = "text",
                        buttons = {
                            {
                                {
                                    text = _("取消"),
                                    callback = function()
                                        UIManager:close(api_key_input)
                                    end,
                                },
                                {
                                    text = _("保存"),
                                    is_enter_default = true,
                                    callback = function()
                                        local key = api_key_input:getInputText()
                                        if key and key ~= "" then
                                            G_reader_settings:saveSetting("deepl_api_key", key)
                                        else
                                            G_reader_settings:delSetting("deepl_api_key")
                                        end
                                        UIManager:close(api_key_input)
                                    end,
                                },
                            },
                        },
                    }
                    UIManager:show(api_key_input)
                    api_key_input:onShowKeyboard()
                end,
            },
            {
                text_func = function()
                    local api_type = G_reader_settings:readSetting("deepl_api_type") or "free"
                    local type_name = api_type == "free" and _("免费") or _("专业版")
                    return T(_("API类型：%1"), type_name)
                end,
                sub_item_table = {
                    {
                        text = _("免费API"),
                        help_text = _([[免费API供个人使用。每月限制500,000字符。]]),
                        checked_func = function()
                            return (G_reader_settings:readSetting("deepl_api_type") or "free") == "free"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("deepl_api_type", "free")
                        end,
                    },
                    {
                        text = _("专业版API"),
                        help_text = _([[专业版API供商业使用。更高限制和优先支持。]]),
                        checked_func = function()
                            return G_reader_settings:readSetting("deepl_api_type") == "pro"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("deepl_api_type", "pro")
                        end,
                    },
                },
                separator = true,
            },
            {
                text_func = function()
                    local lang = G_reader_settings:readSetting("deepl_from_language")
                    return T(_("翻译自：%1"), self:getLanguageName(lang, ""))
                end,
                help_text = _("选择源语言。留空为自动检测。"),
                sub_item_table = genLanguagesItems("deepl_from_language"),
                separator = true,
            },
            {
                text_func = function()
                    local lang = self:getTargetLanguage()
                    return T(_("翻译至：%1"), self:getLanguageName(lang, ""))
                end,
                sub_item_table = genLanguagesItems("deepl_to_language", self:getTargetLanguage()),
            },
        },
    }
end

function DeepLTranslator:getSourceLanguage()
    if G_reader_settings:isFalse("deepl_auto_detect") and
            G_reader_settings:has("deepl_from_language") then
        return G_reader_settings:readSetting("deepl_from_language")
    end
    return AUTODETECT_LANGUAGE
end

function DeepLTranslator:getTargetLanguage()
    local lang = G_reader_settings:readSetting("deepl_to_language")
    if not lang then
        lang = G_reader_settings:readSetting("language")
        if lang and lang ~= "" then
            lang = lang:match("(.*)-") or lang
            if lang == "C" then
                lang = "ZH"
            else
                lang = lang:upper()
            end
        end
    end
    return lang or "ZH"
end

function DeepLTranslator:loadPage(text, target_lang, source_lang)
    local socket = require("socket")
    local socketutil = require("socketutil")
    local url = require("socket.url")
    local http = require("socket.http")
    local ltn12 = require("ltn12")

    local api_key = self:getApiKey()
    if not api_key then
        error(_("DeepL API密钥未配置。请在DeepL设置中设置。"))
    end

    local parsed = url.parse(self:getApiServer())
    parsed.path = self.api_path

    local body = {
        text = { text },
        target_lang = target_lang,
    }

    if source_lang and source_lang ~= AUTODETECT_LANGUAGE then
        body.source_lang = source_lang
    end

    local json_body = JSON.encode(body)

    local sink = {}
    socketutil:set_timeout()

    local request = {
        url = url.build(parsed),
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = #json_body,
            ["Authorization"] = "DeepL-Auth-Key " .. api_key,
        },
        source = ltn12.source.string(json_body),
        sink = ltn12.sink.table(sink),
    }

    logger.dbg("DeepL request:", request.url, "target:", target_lang, "source:", source_lang or "auto")

    local code, headers, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()

    if headers == nil then
        error(status or code or "network unreachable")
    end

    if code ~= 200 then
        logger.warn("DeepL HTTP status not okay:", status or code)
        logger.dbg("Response headers:", headers)
        local response = table.concat(sink)
        logger.dbg("Response body:", response)
        if code == 403 then
            error(_("DeepL API认证失败。请检查您的API密钥。"))
        elseif code == 429 then
            error(_("DeepL API配额已用完。请等待或升级您的计划。"))
        elseif code == 456 then
            error(_("DeepL API配额已用完。"))
        else
            error(_("DeepL翻译失败：") .. (status or tostring(code)))
        end
        return
    end

    local content = table.concat(sink)
    local first_char = content:sub(1, 1)
    if content ~= "" and (first_char == "{" or first_char == "[") then
        local ok, result = pcall(JSON.decode, content)
        if ok and result then
            logger.dbg("DeepL json:", result)
            return result
        else
            logger.warn("DeepL JSON decode error:", result)
        end
    else
        logger.warn("DeepL response is not JSON:", content)
    end
end

function DeepLTranslator:detect(text)
    local result = self:loadPage(text, "EN", AUTODETECT_LANGUAGE)
    if result and result.translations and result.translations[1] then
        local detected_lang = result.translations[1].detected_source_language
        if detected_lang then
            logger.dbg("detected language:", detected_lang)
            return detected_lang
        end
    end
    return self.default_lang
end

function DeepLTranslator:translate(text, target_lang, source_lang)
    if not target_lang then
        target_lang = self:getTargetLanguage()
    end
    if not source_lang then
        source_lang = self:getSourceLanguage()
    end

    local result = self:loadPage(text, target_lang, source_lang)
    if result and result.translations and result.translations[1] then
        return result.translations[1].text
    end
    return nil
end

function DeepLTranslator:showTranslation(text, detailed_view, source_lang, target_lang, from_highlight, index)
    if Device:hasClipboard() then
        Device.input.setClipboardText(text)
    end

    local NetworkMgr = require("ui/network/manager")
    if NetworkMgr:willRerunWhenOnline(function()
                self:showTranslation(text, detailed_view, source_lang, target_lang, from_highlight, index)
            end) then
        return
    end

    local Trapper = require("ui/trapper")
    Trapper:wrap(function()
        self:_showTranslation(text, detailed_view, source_lang, target_lang, from_highlight, index)
    end)
end

function DeepLTranslator:_showTranslation(text, detailed_view, source_lang, target_lang, from_highlight, index)
    if not target_lang then
        target_lang = self:getTargetLanguage()
    end
    if not source_lang then
        source_lang = self:getSourceLanguage()
    end

    local Trapper = require("ui/trapper")
    local completed, result = Trapper:dismissableRunInSubprocess(function()
        return self:loadPage(text, target_lang, source_lang)
    end, _("正在查询DeepL翻译服务…"))

    if not completed then
        UIManager:show(InfoMessage:new{
            text = _("翻译已中断。")
        })
        return
    end

    if not result or not result.translations or not result.translations[1] then
        UIManager:show(InfoMessage:new{
            text = _("翻译失败。")
        })
        return
    end

    local translation = result.translations[1]
    local detected_lang = translation.detected_source_language or source_lang

    local output = {}
    local text_main = translation.text

    if detailed_view then
        table.insert(output, "▣ " .. text)
        if detected_lang and detected_lang ~= AUTODETECT_LANGUAGE then
            table.insert(output, "")
            table.insert(output, T(_("检测到的语言：%1"), self:getLanguageName(detected_lang, detected_lang)))
        end
        table.insert(output, "")
        table.insert(output, "● " .. text_main)
    else
        table.insert(output, text_main)
    end

    local text_all = table.concat(output, "\n")

    local textviewer, height, buttons_table, close_callback
    if detailed_view then
        height = math.floor(Screen:getHeight() * 0.8)
        buttons_table = {}
        if from_highlight then
            local ui = require("apps/reader/readerui").instance
            table.insert(buttons_table,
                {
                    {
                        text = _("保存翻译到笔记"),
                        callback = function()
                            UIManager:close(textviewer)
                            UIManager:close(ui.highlight.highlight_dialog)
                            ui.highlight.highlight_dialog = nil
                            if index then
                                ui.highlight:editNote(index, false, text_main)
                            else
                                ui.highlight:addNote(text_main)
                            end
                        end,
                    },
                }
            )
            close_callback = function()
                if not ui.highlight.highlight_dialog then
                    ui.highlight:clear()
                end
            end
        end
        if Device:hasClipboard() then
            table.insert(buttons_table,
                {
                    {
                        text = _("复制翻译"),
                        callback = function()
                            Device.input.setClipboardText(text_main)
                        end,
                    },
                }
            )
        end
    end

    textviewer = TextViewer:new{
        title = T(_("DeepL翻译自 %1"), self:getLanguageName(detected_lang, "?")),
        title_multilines = true,
        text = text_all,
        text_type = "lookup",
        height = height,
        add_default_buttons = true,
        buttons_table = buttons_table,
        close_callback = close_callback,
    }
    UIManager:show(textviewer)
end

return DeepLTranslator
