-- swayimg 5.4 (Lua config).
-- ВАЖНО: версия 5.4 читает только init.lua. Прежний INI-файл `config`
-- (с `Ctrl+e = exec nemo "%"`) больше не загружается -- поэтому старый
-- бинд на nemo и перестал работать. Этот файл его заменяет.
-- Источник API: /usr/share/swayimg/swayimg.lua

-- Перенесённая настройка из старого config: сглаживание включено.
swayimg.enable_antialiasing(true)

----------------------------------------------------------------------- helpers

-- Безопасное экранирование пути для shell (одинарные кавычки + '\\'' трюк).
-- ОБЯЗАТЕЛЬНО: пути с пробелами / $ / " / ` иначе сломали бы os.execute.
local function shquote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- Ctrl-c: скопировать БАЙТЫ картинки в буфер обмена.
-- mime подбирается через `file`, поэтому корректно для png/jpeg/webp/avif/...
-- Вставится в Telegram/Discord/чат как картинка.
local function copy_image_bytes(img)
  if not img or not img.path then return end
  local q = shquote(img.path)
  os.execute('wl-copy --type "$(file --brief --mime-type ' .. q .. ')" < ' .. q)
end

-- y: скопировать ПУТЬ файла как текст (вставится в терминал/поле ввода).
local function copy_path(img)
  if img and img.path then
    os.execute("wl-copy -- " .. shquote(img.path))
  end
end

-- Ctrl-u: скопировать файл как URI (text/uri-list).
-- Вставка в nemo/файловый менеджер скопирует сам файл.
local function copy_file_uri(img)
  if not img or not img.path then return end
  os.execute("printf 'file://%s\\n' " .. shquote(img.path) .. " | wl-copy --type text/uri-list")
end

-- Ctrl-o: открыть содержащую папку в nemo.
-- `&` + редирект обязательны, иначе os.execute заблокирует swayimg до закрытия окна.
local function open_folder(img)
  if not img or not img.path then return end
  local dir = img.path:match("^(.*)/[^/]*$") or "."
  os.execute("nemo " .. shquote(dir) .. " >/dev/null 2>&1 &")
end

----------------------------------------------------------------------- viewer
swayimg.viewer.on_key("Ctrl-c", function() copy_image_bytes(swayimg.viewer.get_image()) end)
swayimg.viewer.on_key("y",      function() copy_path(swayimg.viewer.get_image()) end)
swayimg.viewer.on_key("Ctrl-u", function() copy_file_uri(swayimg.viewer.get_image()) end)
swayimg.viewer.on_key("Ctrl-o", function() open_folder(swayimg.viewer.get_image()) end)

----------------------------------------------------------------------- gallery
swayimg.gallery.on_key("Ctrl-c", function() copy_image_bytes(swayimg.gallery.get_image()) end)
swayimg.gallery.on_key("y",      function() copy_path(swayimg.gallery.get_image()) end)
swayimg.gallery.on_key("Ctrl-u", function() copy_file_uri(swayimg.gallery.get_image()) end)
swayimg.gallery.on_key("Ctrl-o", function() open_folder(swayimg.gallery.get_image()) end)
