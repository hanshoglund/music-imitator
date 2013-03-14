
{-# LANGUAGE MultiParamTypeClasses, FlexibleInstances #-}

module Music.Imitator.Reactive (
        Chan,
        newChan,
        dupChan,
        writeChan,
        readChan,
        peekChan,
        tryReadChan,
        tryPeekChan,
        Event,
        filterE,
        readE,
        writeE,
        readIOE,
        writeIOE,
        -- MidiSource,
        -- MidiDestination,
        -- midiInE,
        -- midiOutE,
        -- OscMessage,
        -- oscInE,
        -- oscOutE,
        -- linesIn,
        -- linesOut, 
        run,
        runLoop
  ) where

import Data.Monoid
import Data.Traversable
import System.IO.Unsafe

import Control.Newtype
import Control.Concurrent (forkIO, forkOS, threadDelay)
import Control.Monad.STM (atomically)
import Control.Concurrent.STM.TChan


import System.MIDI (MidiMessage,  MidiMessage')
import qualified System.MIDI            as Midi
import qualified Sound.OpenSoundControl as OSC

-- kPortMidiInfo = unsafePerformIO $ do
--     Midi.initialize
--     num  <- Midi.countDevices
--     infos <- Prelude.mapM Midi.getDeviceInfo [0..num - 1]
--     return infos     


-- Factor out channels
newtype Chan a = Chan { getChan :: TChan a }
newChan     :: IO (Chan a)
dupChan     :: Chan a -> IO (Chan a)
writeChan   :: Chan a -> a -> IO ()
readChan    :: Chan a -> IO a
peekChan    :: Chan a -> IO a
tryReadChan :: Chan a -> IO (Maybe a)
tryPeekChan :: Chan a -> IO (Maybe a)
newChan       = atomically . fmap Chan $ newTChan
dupChan c     = atomically . fmap Chan $ dupTChan (getChan c)
writeChan c   = atomically . writeTChan (getChan c)
readChan      = atomically . readTChan . getChan
peekChan      = atomically . peekTChan . getChan
tryReadChan   = atomically . tryReadTChan . getChan
tryPeekChan   = atomically . tryPeekTChan . getChan


newtype Event a = Event { getEvent :: IO (Maybe a) }

-- instance Newtype (Event a) (IO (Maybe a)) where
--     pack    = Event
--     unpack  = getEvent

instance Functor Event where
    fmap f = Event . (fmap (fmap f)) . getEvent

filterE :: (a -> Bool) -> Event a -> Event a
filterE p (Event f) = Event $ do
    x <- f
    case x of
        (Just x) -> if (p x) then return (Just x) else return Nothing
        _        -> return Nothing

instance Monad Event where
    return  = Event . return . return
    (Event f) >>= k = Event $ do
        x <- f
        case x of
            (Just x) -> (getEvent . k) x
            Nothing  -> return Nothing

instance Monoid (Event a) where
    mempty = Event $ return $ Nothing
    Event f `mappend` Event g = Event $ do
        x <- f
        case x of
            (Just x) -> return $ Just x
            _        -> do
                y <- g
                case y of
                    (Just y) -> return $ Just y
                    _        -> return $ Nothing


readIOE :: IO (Maybe a) -> Event a
readIOE = Event

writeIOE :: (a -> IO ()) -> Event a -> Event a
writeIOE g (Event f) = Event $ do
    x <- f
    case x of
        (Just x)  -> g x
        _         -> return ()
    return x


readE :: Chan a -> Event a
readE ch = readIOE (tryReadChan ch)

writeE :: Chan a -> Event a -> Event a
writeE ch e = writeIOE (writeChan ch) e

-- TODO make non-blocking    
linesIn :: Event String
linesIn = readIOE (fmap Just getLine)
-- linesIn = unsafePerformIO $ do
--     ch <- newChan
--     forkIO $ cycleM $ do
--         getLine >>= writeChan ch
--     return $ readE ch 
--     where
--         cycleM x = x >> cycleM x


linesOut :: Event String -> Event String
linesOut = writeIOE putStrLn

-- |
-- Run an event, distributing a single occurance if there is one.
-- 
-- This may result in wrapped actions being executed. 
-- If more than one event refer to a single channel they compete for its contents (i.e. non-determinism).
--
run :: Event a -> IO ()
run (Event f) = do
    x <- f
    return ()

runLoop :: Event a -> IO ()
runLoop e = run e >> threadDelay kloopInterval >> runLoop e  

kloopInterval = 1000 * 5




-- 
-- type MidiSource      = Midi.Source
-- type MidiDestination = Midi.Destination
-- 
-- midiInE :: MidiSource -> Event MidiMessage
-- midiInE = undefined
-- 
-- midiOutE :: MidiDestination -> Event MidiMessage -> Event MidiMessage
-- midiOutE = undefined
-- 
-- type OscMessage = OSC.Message
-- 
-- oscInE :: Int -> Event OscMessage
-- oscInE = undefined
-- 
-- oscOutE :: String -> Int -> Event OscMessage
-- oscOutE = undefined