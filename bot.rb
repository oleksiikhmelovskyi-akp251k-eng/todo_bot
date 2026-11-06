# frozen_string_literal: true

# Бот-Список (To-Do List) для Telegram
# Команди: /start, /help, /add [справа], /list, /done [номер], /clear
# Дані зберігаються в пам'яті: Hash, де ключ — id чату, значення — Ruby Array справ.

require 'telegram/bot'
require 'dotenv/load' # читає змінні з файлу .env

TOKEN = ENV['TELEGRAM_BOT_TOKEN']

if TOKEN.nil? || TOKEN.strip.empty?
  abort 'Помилка: не знайдено TELEGRAM_BOT_TOKEN. Створи файл .env (див. .env.example).'
end

# Сховище справ: { chat_id => ["справа 1", "справа 2", ...] }
# Hash.new { ... } автоматично створює порожній масив для нового користувача,
# тож у кожного свій окремий список.
TODOS = Hash.new { |hash, chat_id| hash[chat_id] = [] }

MAX_ITEM_LENGTH = 200

HELP_TEXT = <<~TEXT
  📋 Я бот-список справ. Команди:

  /add [справа] — додати справу
  /list — показати всі справи
  /done [номер] — видалити одну справу за номером
  /clear — очистити весь список
  /help — ця довідка

  Приклад: /add Купити молоко
TEXT

# Відправка повідомлення (один метод, щоб не повторювати chat_id у кожній гілці)
def reply(bot, message, text)
  bot.api.send_message(chat_id: message.chat.id, text: text)
end

# Розбирає текст на команду і аргумент.
# "/add Купити молоко" -> ["/add", "Купити молоко"]
# "/add@MyBot Купити"  -> ["/add", "Купити"]  (так пишуть команди в групах)
def parse_command(text)
  command, argument = text.strip.split(/\s+/, 2)
  command = command.to_s.downcase.sub(/@\w+\z/, '')
  [command, argument.to_s.strip]
end

def handle_message(bot, message)
  list = TODOS[message.chat.id]
  command, arg = parse_command(message.text)

  case command
  when '/start'
    reply(bot, message, "Привіт, #{message.from&.first_name || 'друже'}! 👋\n\n#{HELP_TEXT}")

  when '/help'
    reply(bot, message, HELP_TEXT)

  when '/add'
    if arg.empty?
      reply(bot, message, "⚠️ Напиши справу після команди.\nПриклад: /add Купити молоко")
    elsif arg.length > MAX_ITEM_LENGTH
      reply(bot, message, "⚠️ Занадто довго (максимум #{MAX_ITEM_LENGTH} символів).")
    else
      list << arg
      reply(bot, message, "✅ Додано: «#{arg}»\nУсього справ: #{list.size}")
    end

  when '/list'
    if list.empty?
      reply(bot, message, '📭 Список порожній. Додай справу: /add [справа]')
    else
      lines = list.each_with_index.map { |item, i| "#{i + 1}. #{item}" }
      reply(bot, message, "📋 Твої справи:\n\n#{lines.join("\n")}")
    end

  when '/done'
    # Перевіряємо, що аргумент — це число в межах списку
    if arg !~ /\A\d+\z/
      reply(bot, message, "⚠️ Вкажи номер справи.\nПриклад: /done 2  (номери дивись у /list)")
    elsif !(1..list.size).cover?(arg.to_i)
      reply(bot, message, "⚠️ Немає справи з номером #{arg}. Усього справ: #{list.size}.")
    else
      removed = list.delete_at(arg.to_i - 1)
      reply(bot, message, "🗑 Виконано і видалено: «#{removed}»")
    end

  when '/clear'
    count = list.size
    list.clear
    reply(bot, message, count.zero? ? '📭 Список і так порожній.' : "🧹 Список очищено (видалено #{count}).")

  else
    if command.start_with?('/')
      reply(bot, message, "❓ Невідома команда #{command}. Напиши /help")
    else
      reply(bot, message, "Щоб додати це як справу, напиши:\n/add #{message.text.strip}")
    end
  end
end

puts 'Бот запущено. Натисни Ctrl+C, щоб зупинити.'

begin
  Telegram::Bot::Client.run(TOKEN) do |bot|
    bot.listen do |message|
      # Нас цікавлять лише звичайні текстові повідомлення
      # (не стікери, фото, натискання кнопок тощо)
      next unless message.is_a?(Telegram::Bot::Types::Message)

      if message.text.nil?
        reply(bot, message, 'Я розумію лише текст 🙂 Напиши /help')
        next
      end

      puts "[#{Time.now.strftime('%H:%M:%S')}] #{message.from&.username || message.chat.id}: #{message.text}"

      begin
        handle_message(bot, message)
      rescue Telegram::Bot::Exceptions::ResponseError => e
        # Помилка від Telegram при відправці (напр. користувач заблокував бота) — бот не падає
        warn "Telegram API помилка: #{e.message}"
      end
    end
  end
rescue Interrupt
  puts "\nБот зупинено."
rescue Telegram::Bot::Exceptions::ResponseError => e
  # Найчастіше — неправильний токен (401 Unauthorized)
  abort "Не вдалося підключитися до Telegram: #{e.message}\nПеревір токен у файлі .env"
end
