module Network.API.Telegram.Bot.Elections.Locales
	(Locale (..), Status (..), message) where

import "base" Text.Read (Read)
import "text" Data.Text (Text)

data Locale = EN | RU deriving Read

data Status = Started | Absented | Proceeded | Considered | Ended

{-# INLINE message #-}
message :: Locale -> Status -> Text
message EN Started = "Voting has begun - now you can vote for the candidates."
message RU Started = "Голосование началось - теперь вы можете голосовать за кандидатов."
message EN Absented = "Elections are not initiated..."
message RU Absented = "Голосование не иницировано..."
message EN Proceeded = "Elections are in progress..."
message RU Proceeded = "Идёт голосование..."
message EN Considered = "Your vote has been counted!"
message RU Considered = "Ваш голос был учтен!"
message EN Ended = "Elections are over, results:"
message RU Ended = "Голосование окончилось, результаты:"
