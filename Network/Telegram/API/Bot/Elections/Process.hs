module Network.Telegram.API.Bot.Elections.Process (initiate, conduct, participate, vote) where

import "base" Control.Applicative (pure, (*>))
import "base" Control.Concurrent (threadDelay)
import "base" Control.Monad ((>>=))
import "base" Data.Foldable (foldr, length)
import "base" Data.Function (const, flip, id, (.), ($))
import "base" Data.Functor (fmap, void, (<$>))
import "base" Data.Int (Int, Int64)
import "base" Data.List (zip)
import "base" Data.Maybe (Maybe (Just, Nothing), maybe)
import "base" Data.Semigroup ((<>))
import "base" Prelude ((*))
import "base" Text.Read (readMaybe)
import "base" Text.Show (show)
import "lens" Control.Lens ((^.))
import "stm" Control.Concurrent.STM (STM, TVar, atomically, modifyTVar', readTVar, writeTVar)
import "text" Data.Text (Text, pack, unpack)
import "telega" Network.Telegram.API.Bot (Telegram, ask')
import "telega" Network.Telegram.API.Bot.Object (Message (Textual)
	, Button (Button), Notification, Pressed (Callback), Keyboard (Inline))
import "telega" Network.Telegram.API.Bot.Object.From (From, firstname, lastname)
import "telega" Network.Telegram.API.Bot.Capacity (drop, edit, post, purge)
import "transformers" Control.Monad.Trans.Class (lift)

import Network.Telegram.API.Bot.Elections.Configuration (Environment)
import Network.Telegram.API.Bot.Elections.Locales (Locale
	, Status (Started, Absented, Proceeded, Considered, Ended), message)
import Network.Telegram.API.Bot.Elections.State (Scores, Votes, nomination, consider)

initiate :: From -> Telegram Environment ()
initiate from = ask' >>= \(locale, chat_id, _, votes) -> (atomically' $ readTVar votes) >>=
	maybe (show_candidates locale chat_id votes) (const $ already_initiated locale chat_id) where

	already_initiated :: Locale -> Int64 -> Telegram Environment ()
	already_initiated locale chat_id = void $ post @Message
		(chat_id, message locale Proceeded, Nothing)

	show_candidates :: Locale -> Int64 -> TVar Votes -> Telegram Environment ()
	show_candidates locale chat_id votes = do
		msg <- post @Message (chat_id, start_voting locale, Just $
			Inline . pure . pure $ button (0, (from, [])))
		let Textual keyboard_msg_id _ _ _ = msg
		atomically' . writeTVar votes . Just $
			(keyboard_msg_id, [(from, [])])

conduct :: Telegram Environment ()
conduct = ask' >>= \(locale, chat_id, election_duration, votes) -> do
	lift . lift . threadDelay $ election_duration * 60000000
	atomically' (readTVar votes) >>= maybe (pure ()) (finish_election locale chat_id votes) where

	finish_election :: Locale -> Int64 -> TVar Votes -> (Int, Scores) -> Telegram Environment ()
	finish_election locale chat_id votes (keyboard_msg_id, scores) = do
		void $ purge @Message (chat_id, keyboard_msg_id)
		void $ post @Message (chat_id, end_voting locale scores, Nothing)
		atomically' . writeTVar votes $ Nothing

participate :: From -> Telegram Environment ()
participate from = ask' >>= \(locale, chat_id, _, votes) -> atomically' (readTVar votes) >>= \case
	Nothing -> void $ post @Message (chat_id, message locale Absented, Nothing)
	Just (keyboard_msg_id, scores) -> flip (maybe (pure ())) (nomination from scores) $ \upd -> do
		let new_keyboard = Inline $ pure . button <$> zip [0..] upd
		atomically' $ writeTVar votes $ Just (keyboard_msg_id, upd)
		void $ edit @Keyboard (chat_id, keyboard_msg_id, new_keyboard)

vote :: Text -> From -> Text -> Telegram Environment ()
vote _ _ (readMaybe @Int . unpack -> Nothing) = pure ()
vote cbq_id from (readMaybe @Int . unpack -> Just cnd_idx) = ask' >>= \(locale, chat_id, _, votes) -> do
	let considering = modifyTVar' votes (fmap . fmap $ consider cnd_idx from) *> readTVar votes
	atomically' considering >>= maybe (pure ()) (adjuct_scores locale chat_id) where

	adjuct_scores :: Locale -> Int64 -> (Int, Scores) -> Telegram Environment ()
	adjuct_scores locale chat_id (keyboard_msg_id, scores) = do
		void $ drop @Notification (cbq_id, message locale Considered)
		void $ edit @Keyboard (chat_id, keyboard_msg_id
			, Inline $ pure . button <$> zip [0..] scores)

atomically' :: STM a -> Telegram Environment a
atomically' = lift . lift . atomically

button :: (Int, (From, [From])) -> Button
button (idx, (from, n)) = flip Button (Callback . pack . show $ idx) $
	from ^. firstname <> " " <> maybe "" id (from ^. lastname)
		<> " : " <> (pack . show . length $ n)

start_voting :: Locale -> Text
start_voting = flip message Started

end_voting :: Locale -> Scores -> Text
end_voting locale scores = message locale Ended <> "\n" <>
	foldr (\x acc -> line x <> acc) "" scores where

	line :: (From, [From]) -> Text
	line (from, voters) = "* " <> from ^. firstname
		<> " " <> maybe "" id (from ^. lastname)
		<> " : " <> (pack . show . length $ voters) <> "\n"
