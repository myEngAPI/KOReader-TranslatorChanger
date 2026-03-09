--[[--
DeepSeek Translation Plugin for KOReader

This module provides DeepSeek translation engine as an alternative to Google Translate.
It uses the DeepSeek API (OpenAI-compatible) to translate text with better quality for users in China.

DeepSeek API Documentation:
- Base URL: https://api.deepseek.com
- Endpoint: /chat/completions
- Get API key: https://platform.deepseek.com/
- API Docs: https://api-docs.deepseek.com/zh-cn/

@module koplugin.DeepSeekTranslator
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

local DeepSeekTranslator = {
    base_url = "https://api.deepseek.com",
    api_key = nil,
    model = "deepseek-chat",
    default_lang = "ZH",
}

function DeepSeekTranslator:getBaseUrl()
    local base_url = G_reader_settings:readSetting("deepseek_base_url") or self.base_url
    return base_url
end

function DeepSeekTranslator:getApiEndpoint()
    local base_url = self:getBaseUrl()
    return base_url .. "/chat/completions"
end

function DeepSeekTranslator:getApiKey()
    local api_key = G_reader_settings:readSetting("deepseek_api_key")
    if not api_key or api_key == "" then
        return nil
    end
    return api_key
end

function DeepSeekTranslator:getModel()
    local model = G_reader_settings:readSetting("deepseek_model") or self.model
    return model
end

function DeepSeekTranslator:getLanguageName(lang, default_string)
    local lang_names = {
        ZH = _("中文（简体）"),
        EN = _("英语"),
        JA = _("日语"),
        KO = _("韩语"),
        FR = _("法语"),
        DE = _("德语"),
        ES = _("西班牙语"),
        RU = _("俄语"),
        IT = _("意大利语"),
        PT = _("葡萄牙语"),
        AR = _("阿拉伯语"),
        HI = _("印地语"),
    }
    if lang_names[lang] then
        return lang_names[lang], true
    elseif lang then
        return lang:upper(), false
    end
    return default_string, false
end

function DeepSeekTranslator:genSettingsMenu()
    return {
        text = _("DeepSeek设置"),
        sub_item_table = {
            {
                text = _("API密钥"),
                help_text = _([[输入您的DeepSeek API密钥。获取API密钥：https://platform.deepseek.com/]]),
                keep_menu_open = true,
                callback = function()
                    local InputDialog = require("ui/widget/inputdialog")
                    local api_key_input
                    api_key_input = InputDialog:new{
                        title = _("DeepSeek API密钥"),
                        input = G_reader_settings:readSetting("deepseek_api_key") or "",
                        input_hint = "sk-xxxxxxxxxxxxxxxxxxxxxxxx",
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
                                            G_reader_settings:saveSetting("deepseek_api_key", key)
                                        else
                                            G_reader_settings:delSetting("deepseek_api_key")
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
                text = _("Base URL"),
                help_text = _([[DeepSeek API基础URL。默认：https://api.deepseek.com]]),
                keep_menu_open = true,
                callback = function()
                    local InputDialog = require("ui/widget/inputdialog")
                    local base_url_input
                    base_url_input = InputDialog:new{
                        title = _("DeepSeek Base URL"),
                        input = G_reader_settings:readSetting("deepseek_base_url") or self.base_url,
                        input_hint = "https://api.deepseek.com",
                        input_type = "text",
                        buttons = {
                            {
                                {
                                    text = _("取消"),
                                    callback = function()
                                        UIManager:close(base_url_input)
                                    end,
                                },
                                {
                                    text = _("保存"),
                                    is_enter_default = true,
                                    callback = function()
                                        local url = base_url_input:getInputText()
                                        if url and url ~= "" then
                                            G_reader_settings:saveSetting("deepseek_base_url", url)
                                        else
                                            G_reader_settings:delSetting("deepseek_base_url")
                                        end
                                        UIManager:close(base_url_input)
                                    end,
                                },
                            },
                        },
                    }
                    UIManager:show(base_url_input)
                    base_url_input:onShowKeyboard()
                end,
            },
            {
                text_func = function()
                    local model = self:getModel()
                    local model_names = {
                        ["deepseek-chat"] = _("DeepSeek Chat（非思考模式）"),
                        ["deepseek-reasoner"] = _("DeepSeek Reasoner（思考模式）"),
                    }
                    return T(_("模型：%1"), model_names[model] or model)
                end,
                sub_item_table = {
                    {
                        text = _("DeepSeek Chat（非思考模式）"),
                        help_text = _([[标准对话模型，响应快速。]]),
                        checked_func = function()
                            return self:getModel() == "deepseek-chat"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("deepseek_model", "deepseek-chat")
                        end,
                    },
                    {
                        text = _("DeepSeek Reasoner（思考模式）"),
                        help_text = _([[思考模型，提供更深入的推理。响应较慢。]]),
                        checked_func = function()
                            return self:getModel() == "deepseek-reasoner"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("deepseek_model", "deepseek-reasoner")
                        end,
                    },
                },
                separator = true,
            },
            {
                text_func = function()
                    local api_key = G_reader_settings:readSetting("deepseek_api_key")
                    if api_key and api_key ~= "" then
                        return _("API密钥：已设置")
                    else
                        return _("API密钥：未设置")
                    end
                end,
                enabled_func = function()
                    return false
                end,
            },
        },
    }
end

function DeepSeekTranslator:getTargetLanguage()
    local lang = G_reader_settings:readSetting("deepseek_to_language")
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

function DeepSeekTranslator:loadPage(text, target_lang, source_lang)
    local socket = require("socket")
    local socketutil = require("socketutil")
    local url = require("socket.url")
    local http = require("socket.http")
    local ltn12 = require("ltn12")

    local debug_info = {}
    table.insert(debug_info, "=== DeepSeek翻译调试信息 ===")
    table.insert(debug_info, "")

    local api_key = self:getApiKey()
    if not api_key then
        table.insert(debug_info, "❌ API密钥未配置")
        table.insert(debug_info, "请在DeepSeek设置中设置API密钥")
        return { success = false, error = table.concat(debug_info, "\n") }
    end

    table.insert(debug_info, "✅ API密钥已配置: " .. string.sub(api_key, 1, 8) .. "...")

    local api_endpoint = self:getApiEndpoint()
    table.insert(debug_info, "📡 API端点: " .. api_endpoint)

    local parsed = url.parse(api_endpoint)
    table.insert(debug_info, "🔗 解析后的URL: " .. url.build(parsed))

    local lang_names = {
        ZH = "中文（简体）",
        EN = "英语",
        JA = "日语",
        KO = "韩语",
        FR = "法语",
        DE = "德语",
        ES = "西班牙语",
        RU = "俄语",
        IT = "意大利语",
        PT = "葡萄牙语",
        AR = "阿拉伯语",
        HI = "印地语",
    }

    local target_lang_name = lang_names[target_lang] or target_lang
    local system_prompt = "你是一个专业的翻译助手。请将以下文本翻译成" .. target_lang_name .. "。只返回翻译结果，不要添加任何解释或额外内容。"

    local model = self:getModel()
    table.insert(debug_info, "🤖 模型: " .. model)
    table.insert(debug_info, "🌐 目标语言: " .. target_lang .. " (" .. target_lang_name .. ")")
    table.insert(debug_info, "")

    local body = {
        model = model,
        messages = {
            { role = "system", content = system_prompt },
            { role = "user", content = text },
        },
        stream = false,
    }

    local json_body = JSON.encode(body)
    table.insert(debug_info, "📤 发送的请求Body:")
    table.insert(debug_info, json_body)
    table.insert(debug_info, "")

    local sink = {}
    socketutil:set_timeout()

    local request = {
        url = url.build(parsed),
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = #json_body,
            ["Authorization"] = "Bearer " .. api_key,
        },
        source = ltn12.source.string(json_body),
        sink = ltn12.sink.table(sink),
    }

    table.insert(debug_info, "📋 发送的请求Headers:")
    table.insert(debug_info, "  Content-Type: application/json")
    table.insert(debug_info, "  Content-Length: " .. #json_body)
    table.insert(debug_info, "  Authorization: Bearer " .. string.sub(api_key, 1, 8) .. "...")
    table.insert(debug_info, "")

    logger.dbg("DeepSeek request:", request.url, "model:", model, "target:", target_lang)

    local code, headers, status
    local max_retries = 5
    local retry_delay = 2
    local retry_count = 0

    -- 增加socket超时设置
    socketutil:set_timeout(60)

    while retry_count < max_retries do
        code, headers, status = socket.skip(1, http.request(request))
        
        -- 检查是否是wantread错误或连接错误
        if status and (status:find("wantread") or status:find("WANTREAD") or status:find("timeout") or status:find("TIMEOUT")) then
            retry_count = retry_count + 1
            table.insert(debug_info, "🔄 遇到网络错误(" .. tostring(status) .. ")，正在重试... (" .. retry_count .. "/" .. max_retries .. ")")
            socket.sleep(retry_delay)
            retry_delay = retry_delay * 1.2 -- 调整退避策略
        else
            break
        end
    end

    socketutil:reset_timeout()

    table.insert(debug_info, "📊 HTTP状态码: " .. tostring(code or "无"))

    if headers == nil then
        table.insert(debug_info, "❌ 网络错误: " .. (status or code or "未知错误"))
        table.insert(debug_info, "请检查网络连接")
        return { success = false, error = table.concat(debug_info, "\n") }
    end

    table.insert(debug_info, "📥 接收到的响应Headers:")
    for k, v in pairs(headers) do
        table.insert(debug_info, "  " .. k .. ": " .. v)
    end
    table.insert(debug_info, "")

    local response = table.concat(sink)
    table.insert(debug_info, "📄 接收到的响应Body:")
    table.insert(debug_info, response)
    table.insert(debug_info, "")

    if code ~= 200 then
        logger.warn("DeepSeek HTTP status not okay:", status or code)
        logger.dbg("Response headers:", headers)
        logger.dbg("Response body:", response)
        
        local error_msg = ""
        if code == 401 then
            error_msg = "API认证失败。请检查您的API密钥。"
        elseif code == 429 then
            error_msg = "API配额已用完。请等待或升级您的计划。"
        else
            error_msg = "翻译失败：" .. (status or tostring(code))
        end
        
        table.insert(debug_info, "❌ " .. error_msg)
        return { success = false, error = table.concat(debug_info, "\n") }
    end

    local first_char = response:sub(1, 1)
    if response ~= "" and (first_char == "{" or first_char == "[") then
        local ok, result = pcall(JSON.decode, response)
        if ok and result then
            logger.dbg("DeepSeek json:", result)
            table.insert(debug_info, "✅ JSON解析成功")
            result._debug_info = table.concat(debug_info, "\n")
            return result
        else
            logger.warn("DeepSeek JSON decode error:", result)
            table.insert(debug_info, "❌ JSON解析失败: " .. tostring(result))
            return { success = false, error = table.concat(debug_info, "\n") }
        end
    else
        logger.warn("DeepSeek response is not JSON:", response)
        table.insert(debug_info, "❌ 响应不是有效的JSON格式")
        return { success = false, error = table.concat(debug_info, "\n") }
    end
end

function DeepSeekTranslator:detect(text)
    local result = self:loadPage(text, "EN", nil)
    if result and result.success and result.result and result.result.choices and result.result.choices[1] then
        return "EN"
    end
    return self.default_lang
end

function DeepSeekTranslator:translate(text, target_lang, source_lang)
    if not target_lang then
        target_lang = self:getTargetLanguage()
    end

    local result = self:loadPage(text, target_lang, source_lang)
    if result and result.choices and result.choices[1] then
        return result.choices[1].message.content
    end
    return nil
end

function DeepSeekTranslator:showTranslation(text, detailed_view, source_lang, target_lang, from_highlight, index)
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

function DeepSeekTranslator:_showTranslation(text, detailed_view, source_lang, target_lang, from_highlight, index)
    if not target_lang then
        target_lang = self:getTargetLanguage()
    end

    local result = self:loadPage(text, target_lang, source_lang)

    local output = {}
    local translation = nil
    local debug_info = nil

    if result then
        if result.choices and result.choices[1] and result.choices[1].message then
            translation = result.choices[1].message.content
            debug_info = result._debug_info
        else
            debug_info = result.error or "❌ 未收到有效的翻译结果"
        end
    else
        debug_info = "❌ 未收到任何返回结果"
    end

    if not translation then
        table.insert(output, "❌ 翻译失败")
        table.insert(output, "")
        if debug_info then
            table.insert(output, debug_info)
        end
        UIManager:show(TextViewer:new{
            title = _("DeepSeek翻译错误"),
            title_multilines = true,
            text = table.concat(output, "\n"),
            text_type = "lookup",
            height = math.floor(Screen:getHeight() * 0.8),
            add_default_buttons = true,
        })
        return
    end

    local detected_lang = source_lang or target_lang

    if detailed_view then
        table.insert(output, "▣ " .. text)
        table.insert(output, "")
        table.insert(output, "● " .. translation)
    else
        table.insert(output, translation)
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
                                ui.highlight:editNote(index, false, translation)
                            else
                                ui.highlight:addNote(translation)
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
                            Device.input.setClipboardText(translation)
                        end,
                    },
                }
            )
        end
    end

    textviewer = TextViewer:new{
        title = T(_("DeepSeek翻译至 %1"), self:getLanguageName(detected_lang, "?")),
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

return DeepSeekTranslator
