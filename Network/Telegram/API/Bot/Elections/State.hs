module Network.Telegram.API.Bot.Elections.State (Scores, Votes, nomination, consider) where

import "base" Data.Eq ((==))
import "base" Data.Foldable (find)
import "base" Data.Function (const, (.), ($), (&))
import "base" Data.Functor (fmap)
import "base" Data.Int (Int)
import "base" Data.List (delete)
import "base" Data.Maybe (Maybe, maybe)
import "base" Data.Tuple (fst)
import "lens" Control.Lens (element, _2, (%~))
import "telega" Network.Telegram.API.Bot.Object.From (From)

type Scores = [(From, [From])]

type Votes = Maybe (Int, Scores)

-- Application for participation
nomination :: From -> Votes -> Votes
nomination user = fmap . fmap $ \us ->
	maybe ((user, []) : us) (const us) . find ((==) user . fst) $ us

-- If you already voted for this candidate, your vote will be removed
consider :: Int -> From -> Scores -> Scores
consider candidate_index voter votes = votes & element candidate_index . _2 %~
	(\scores -> maybe (voter : scores) (const $ delete voter scores) . find (== voter) $ scores)
