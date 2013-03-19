
module Music.Imitator.Reactive.Midi (
        module Codec.Midi,
        MidiName,
        MidiSource,
        MidiDestination,
        midiSources,
        midiDestinations,
        findSource,
        findDestination,
        midiIn,
        midiOut,
  ) where

import Data.Monoid  
import Data.Maybe
import Control.Monad
import Control.Applicative
import Control.Newtype
import Control.Concurrent (forkIO, threadDelay)
import System.IO.Unsafe

import Music.Imitator.Reactive
import Music.Imitator.Util

import Codec.Midi hiding (Time)
import qualified System.MIDI            as Midi


type MidiName        = String
type MidiSource      = Midi.Source
type MidiDestination = Midi.Destination


midiSources :: Reactive [MidiSource]
midiSources = eventToReactive 
        (pollE $ threadDelay 1 >> Midi.sources >>= return . Just)

midiDestinations :: Reactive [MidiDestination]
midiDestinations = eventToReactive 
        (pollE $ threadDelay 1 >> Midi.destinations >>= return . Just)

findSource :: Reactive String -> Reactive (Maybe MidiSource)
findSource nm = g <$> nm <*> midiSources
    where
        g = (\n -> listToMaybe . filter (\d -> isSubstringOfNormalized n $ unsafePerformIO (Midi.name d)))

findDestination :: Reactive String -> Reactive (Maybe MidiDestination)
findDestination nm = g <$> nm <*> midiDestinations
    where
        g = (\n -> listToMaybe . filter (\d -> isSubstringOfNormalized n $ unsafePerformIO (Midi.name d)))

midiIn :: MidiSource -> Event Message
midiIn = undefined

midiOut :: MidiDestination -> Event Message -> Event Message
midiOut dest = putE $ \msg -> do
    Midi.send dest' msg
    where
        dest' = unsafePerformIO $ do
            -- putStrLn "Midi.openDestination"
            Midi.openDestination dest








---------

eventToReactive :: Event a -> Reactive a
eventToReactive = stepper (error "eventToReactive: ")

