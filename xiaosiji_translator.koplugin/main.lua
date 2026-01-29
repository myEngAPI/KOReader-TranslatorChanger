--[[--
小司机翻译配置插件

多翻译引擎插件，支持DeepL和DeepSeek翻译。在中国提供更好的翻译质量。

@module koplugin.xiaosijitranslatorplugin
--]]

local DeepLTranslator = require("deepl_translator")
local DeepSeekTranslator = require("deepseek_translator")
local OpenAITranslator = require("openai_translator")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local logger = require("logger")
local _ = require("gettext")
local T = ffiUtil.template

local xiaosijitranslatorplugin = WidgetContainer:extend{
    name = "xiaosiji_translator",
    is_doc_only = false,
}

function xiaosijitranslatorplugin:init()
    logger.dbg("小司机翻译配置插件: init called")
    self.ui.menu:registerToMainMenu(self)
    logger.dbg("小司机翻译配置插件: registered to main menu")
    
    self:patchTranslator()
    
    if self.ui.highlight then
        self:patchHighlightModule()
    end
end

function xiaosijitranslatorplugin:patchTranslator()
    local Translator = require("ui/translator")

    if not self.original_translate then
        self.original_translate = Translator.translate
        self.original_showTranslation = Translator.showTranslation
        logger.dbg("小司机翻译配置插件: saved original translator methods")
    end

    local engine = G_reader_settings:readSetting("translator_engine") or "google"
    if engine == "deepl" then
        logger.dbg("小司机翻译配置插件: patching translator with DeepL")
        Translator.translate = function(self, text, target_lang, source_lang)
            return DeepLTranslator:translate(text, target_lang, source_lang)
        end

        Translator.showTranslation = function(self, text, detailed_view, source_lang, target_lang, from_highlight, index)
            return DeepLTranslator:showTranslation(text, detailed_view, source_lang, target_lang, from_highlight, index)
        end

        logger.dbg("小司机翻译配置插件: DeepL translator patched successfully")
    elseif engine == "deepseek" then
        logger.dbg("小司机翻译配置插件: patching translator with DeepSeek")
        Translator.translate = function(self, text, target_lang, source_lang)
            return DeepSeekTranslator:translate(text, target_lang, source_lang)
        end

        Translator.showTranslation = function(self, text, detailed_view, source_lang, target_lang, from_highlight, index)
            return DeepSeekTranslator:showTranslation(text, detailed_view, source_lang, target_lang, from_highlight, index)
        end

        logger.dbg("小司机翻译配置插件: DeepSeek translator patched successfully")
    elseif engine == "openai" then
        logger.dbg("小司机翻译配置插件: patching translator with OpenAI")
        Translator.translate = function(self, text, target_lang, source_lang)
            return OpenAITranslator:translate(text, target_lang, source_lang)
        end

        Translator.showTranslation = function(self, text, detailed_view, source_lang, target_lang, from_highlight, index)
            return OpenAITranslator:showTranslation(text, detailed_view, source_lang, target_lang, from_highlight, index)
        end

        logger.dbg("小司机翻译配置插件: OpenAI translator patched successfully")
    else
        logger.dbg("小司机翻译配置插件: using original Google translator")
        if self.original_translate then
            Translator.translate = self.original_translate
        end
        if self.original_showTranslation then
            Translator.showTranslation = self.original_showTranslation
        end
    end
end

function xiaosijitranslatorplugin:patchHighlightModule()
    if not self.ui.highlight then
        return
    end

    local ReaderHighlight = self.ui.highlight

    if not self.original_highlightShowTranslation then
        self.original_highlightShowTranslation = ReaderHighlight.showTranslation
        logger.dbg("小司机翻译配置插件: saved highlight showTranslation method")
    end

    local engine = G_reader_settings:readSetting("translator_engine") or "google"

    if engine == "deepl" then
        logger.dbg("小司机翻译配置插件: patching highlight module with DeepL")
        ReaderHighlight.showTranslation = function(self, text, detailed_view, source_lang, target_lang, from_highlight, index)
            return DeepLTranslator:showTranslation(text, detailed_view, source_lang, target_lang, from_highlight, index)
        end
    elseif engine == "deepseek" then
        logger.dbg("小司机翻译配置插件: patching highlight module with DeepSeek")
        ReaderHighlight.showTranslation = function(self, text, detailed_view, source_lang, target_lang, from_highlight, index)
            return DeepSeekTranslator:showTranslation(text, detailed_view, source_lang, target_lang, from_highlight, index)
        end
    elseif engine == "openai" then
        logger.dbg("小司机翻译配置插件: patching highlight module with OpenAI")
        ReaderHighlight.showTranslation = function(self, text, detailed_view, source_lang, target_lang, from_highlight, index)
            return OpenAITranslator:showTranslation(text, detailed_view, source_lang, target_lang, from_highlight, index)
        end
    else
        if self.original_highlightShowTranslation then
            ReaderHighlight.showTranslation = self.original_highlightShowTranslation
        end
    end
end

function xiaosijitranslatorplugin:addToMainMenu(menu_items)
    logger.dbg("小司机翻译配置插件: addToMainMenu called")
    
    menu_items.xiaosiji_translator = {
        text = _("小司机翻译配置"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text_func = function()
                    local engine = G_reader_settings:readSetting("translator_engine") or "google"
                    local engine_names = {
                        google = _("Google翻译"),
                        deepl = _("DeepL翻译"),
                        deepseek = _("DeepSeek翻译"),
                        openai = _("通用OpenAI翻译"),
                    }
                    return T(_("当前：%1"), engine_names[engine] or engine)
                end,
                sub_item_table = {
                    {
                        text = _("Google翻译"),
                        help_text = _("使用默认的Google翻译引擎"),
                        checked_func = function()
                            return (G_reader_settings:readSetting("translator_engine") or "google") == "google"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("translator_engine", "google")
                            self:patchTranslator()
                            self:patchHighlightModule()
                            UIManager:show(require("ui/widget/infomessage"):new{
                                text = _("Google翻译引擎已启用\n请重启KOReader生效"),
                            })
                        end,
                    },
                    {
                        text = _("DeepL翻译"),
                        help_text = _("使用DeepL翻译引擎，翻译质量好，需要API密钥"),
                        checked_func = function()
                            return G_reader_settings:readSetting("translator_engine") == "deepl"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("translator_engine", "deepl")
                            self:patchTranslator()
                            self:patchHighlightModule()
                            UIManager:show(require("ui/widget/infomessage"):new{
                                text = _("DeepL翻译引擎已启用\n请重启KOReader生效"),
                            })
                        end,
                    },
                    {
                        text = _("DeepSeek翻译"),
                        help_text = _("使用DeepSeek翻译引擎，翻译质量好，需要API密钥"),
                        checked_func = function()
                            return G_reader_settings:readSetting("translator_engine") == "deepseek"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("translator_engine", "deepseek")
                            self:patchTranslator()
                            self:patchHighlightModule()
                            UIManager:show(require("ui/widget/infomessage"):new{
                                text = _("DeepSeek翻译引擎已启用\n请重启KOReader生效"),
                            })
                        end,
                    },
                    {
                        text = _("通用OpenAI翻译"),
                        help_text = _("使用OpenAI兼容API翻译引擎，如硅基流动，需要API密钥"),
                        checked_func = function()
                            return G_reader_settings:readSetting("translator_engine") == "openai"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("translator_engine", "openai")
                            self:patchTranslator()
                            self:patchHighlightModule()
                            UIManager:show(require("ui/widget/infomessage"):new{
                                text = _("通用OpenAI翻译引擎已启用\n请重启KOReader生效"),
                            })
                        end,
                    },
                },
                separator = true,
            },
            DeepLTranslator:genSettingsMenu(),
            DeepSeekTranslator:genSettingsMenu(),
            OpenAITranslator:genSettingsMenu(),
        },
    }
end

require("insert_menu")

return xiaosijitranslatorplugin
