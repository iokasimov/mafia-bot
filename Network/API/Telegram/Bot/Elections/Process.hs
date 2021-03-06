module Network.API.Telegram.Bot.Elections.Process (initiate, conduct, participate, vote) where

import "base" Control.Applicative (pure, (*>))
import "base" Control.Concurrent (threadDelay)
import "base" Control.Monad ((>>=))
import "base" Data.Foldable (foldr, length)
import "base" Data.Function (const, flip, (.), ($))
import "base" Data.Functor (fmap, (<$>))
import "base" Data.Int (Int)
import "base" Data.List (zip)
import "base" Data.Maybe (Maybe (Just, Nothing), maybe)
import "base" Data.Semigroup ((<>))
import "base" Prelude ((*))
import "base" Text.Read (readMaybe)
import "base" Text.Show (show)
import "lens" Control.Lens (view, (^.))
import "stm" Control.Concurrent.STM (STM, TVar, atomically, modifyTVar', readTVar, writeTVar)
import "text" Data.Text (Text, pack, unpack)
import "telega" Network.API.Telegram.Bot (Telegram, environment)
import "telega" Network.API.Telegram.Bot.Field.Name (Name, First, Last)
import "telega" Network.API.Telegram.Bot.Object (Chat, Sender, Button (Button), Content (Textual), Pressed (Callback), Keyboard (Inline))
import "telega" Network.API.Telegram.Bot.Object.Update.Message (Message (Direct), Send (Send), Edit (Edit), Delete (Delete))
import "telega" Network.API.Telegram.Bot.Property (ID, access, persist, persist_)
import "telega" Network.API.Telegram.Bot.Utils (type (:*:)((:*:)))
import "joint" Control.Joint (lift)

import Network.API.Telegram.Bot.Elections.Configuration (Environment)
import Network.API.Telegram.Bot.Elections.Locales (Locale, Status (Started, Absented, Proceeded, Ended), message)
import Network.API.Telegram.Bot.Elections.State (Scores, Votes, nomination, consider)

-- Initiate elections, the initiator becomes a candidate automatically
initiate :: Sender -> Telegram Environment ()
initiate sender = environment >>= \(locale, chat_id, _, votes) -> atomically' (readTVar votes) >>=
	maybe (show_candidates locale chat_id votes) (const $ already_initiated locale chat_id) where

	already_initiated :: Locale -> ID Chat -> Telegram Environment ()
	already_initiated locale chat_id = persist_ . Send chat_id $ message locale Proceeded

	show_candidates :: Locale -> ID Chat -> TVar Votes -> Telegram Environment ()
	show_candidates locale chat_id votes = do
		let keyboard = Inline . pure . pure $ button (0, (sender, []))
		msg <- persist . Send chat_id $ start_voting locale :*: keyboard
		let Direct keyboard_msg_id _ (Textual _) = msg
		atomically' . writeTVar votes . Just $
			(keyboard_msg_id, [(sender, [])])

	start_voting :: Locale -> Text
	start_voting = flip message Started

-- After some election period summarize all scores for each candidate
conduct :: Telegram Environment ()
conduct = environment >>= \(locale, chat_id, election_duration, votes) -> do
	lift . threadDelay $ election_duration * 60000000
	atomically' (readTVar votes) >>= maybe (pure ()) (finish_election locale chat_id votes) where

	finish_election :: Locale -> ID Chat -> TVar Votes -> (ID Message, Scores) -> Telegram Environment ()
	finish_election locale chat_id votes (keyboard_msg_id, scores) = do
		persist_ $ Delete @Message chat_id keyboard_msg_id
		persist_ . Send chat_id $ end_voting locale scores
		atomically' . writeTVar votes $ Nothing

	end_voting :: Locale -> Scores -> Text
	end_voting locale scores = message locale Ended <> "\n" <>
		foldr (\x acc -> line x <> acc) "" scores where

		line :: (Sender, [Sender]) -> Text
		line (sender, voters) = "* " <> (sender ^. access @(First Name) . access @Text)
			<> " " <> maybe "" (view $ access @Text) (sender ^. access @(Maybe (Last Name)))
			<> " : " <> (pack . show . length $ voters) <> "\n"

-- Become a candidate
participate :: Sender -> Telegram Environment ()
participate sender = environment >>= \(locale, chat_id, _, votes) -> atomically' (readTVar votes) >>= \case
	Nothing -> persist_ $ Send chat_id $ message locale Absented
	Just (keyboard_msg_id, scores) -> flip (maybe (pure ())) (nomination sender scores) $ \upd -> do
		let new_keyboard = Inline $ pure . button <$> zip [0..] upd
		atomically' $ writeTVar votes $ Just (keyboard_msg_id, upd)
		persist_ $ Edit chat_id keyboard_msg_id new_keyboard

-- 👍 or 👎 for some candidate
vote :: Sender -> Text -> Telegram Environment ()
vote _ (readMaybe @Int . unpack -> Nothing) = pure ()
vote sender (readMaybe @Int . unpack -> Just cnd_idx) = environment >>= \(_, chat_id, _, votes) -> do
	let considering = modifyTVar' votes (fmap . fmap $ consider cnd_idx sender) *> readTVar votes
	atomically' considering >>= maybe (pure ()) (adjust_scores chat_id) where

	adjust_scores :: ID Chat -> (ID Message, Scores) -> Telegram Environment ()
	adjust_scores chat_id (keyboard_msg_id, scores) = do
		persist_ . Edit @Keyboard chat_id keyboard_msg_id . Inline $
			pure . button <$> zip [0..] scores

button :: (Int, (Sender, [Sender])) -> Button
button (idx, (sender, n)) = flip Button (Callback . pack . show $ idx) $
	(sender ^. access @(First Name) . access @Text) <> " "
	<> maybe "" (view $ access @Text) (sender ^. access @(Maybe (Last Name)))
	<> " : " <> (pack . show . length $ n)

atomically' :: STM a -> Telegram Environment a
atomically' = lift . atomically
