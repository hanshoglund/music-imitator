
{-# LANGUAGE GADTs #-}

module Music.Imitator.Reactive (
        Chan(..),
        newChan,
        dupChan,
        readChan,
        tryReadChan,
        writeChan,
        
        -- * Events
        Event,

        -- ** Combine events
        neverE,
        -- alwaysE,
        mergeE,
        sequenceE,
        -- mergeWithE,

        -- ** Change value of events
        tickE,
        tickME,          
        mapE,
        filterE,
        -- -- MidiSource,
        -- -- MidiDestination,
        -- -- midiInE,
        -- -- midiOutE,
        -- -- OscMessage,
        -- -- oscInE,
        -- -- oscOutE,

        -- ** Create events
        -- *** From standard library
        getLineE,
        putLineE, 

        -- *** From channels
        readChanE,
        writeChanE,

        -- *** From I/O computations
        getE,
        pollE,
        putE,
        -- modifyE,                 
        
        -- ** Run events
        run,
        runLoop,
        runLoopUntil,
        
        
        -- * Reactive values
        Reactive,
        stepper,
        switcher,
        sample,
  ) where

import Prelude hiding (mapM)

import Data.Monoid  
import Data.Maybe

import Control.Monad
import Control.Applicative
import Control.Newtype

import Control.Concurrent (forkIO, forkOS, threadDelay)
import Control.Monad.STM (atomically)
import Control.Concurrent.STM.TChan
import Control.Concurrent.STM.TMVar

import System.IO.Unsafe


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
tryReadChan :: Chan a -> IO (Maybe a)

newChan               = do
    c' <- atomically $ newTChan
    return (Chan c')

dupChan (Chan c)      = do
    c' <- atomically . dupTChan $ c
    return (Chan c')    

writeChan (Chan c) x  = atomically $ writeTChan c x
readChan  (Chan c)    = atomically $ readTChan c
tryReadChan (Chan c)  = atomically $ tryReadTChan c


data Event a where
    ENever  :: Event a
    EMerge  :: Event a -> Event a -> Event a
    ESeq    :: Event a -> Event b -> Event b

    EMap    :: (a -> b) -> Event a -> Event b
    EPred   :: (a -> Bool) -> Event a -> Event a

    EChan   :: Chan a       -> Event a
    ESource :: IO [a]       -> Event a
    ESink   :: (a -> IO b)  -> Event a -> Event b

prepChan :: Chan a -> IO (IO [a])
prepChan ch = do
    ch' <- dupChan ch
    return $ fmap maybeToList $ tryReadChan ch'

prepare :: Event a -> IO (Event a)
prepare (EChan ch)      = do
    ch' <- prepChan ch
    return $ ESource ch' 
prepare (EMerge a b)     = do
    a' <- prepare a
    b' <- prepare b
    return $ EMerge a' b'
prepare (ESeq a b)     = do
    a' <- prepare a
    b' <- prepare b
    return $ ESeq a' b'
prepare (EMap f x)    = do
    x' <- prepare x
    return $ EMap f x'
prepare (EPred p x)    = do
    x' <- prepare x
    return $ EPred p x'
prepare (ESink k a)     = do
    a' <- prepare a
    return $ ESink k a'
prepare x               = return x

-- | 
-- Run the given event once.
--
run :: Event a -> IO ()
run e = do
    e' <- prepare e
    run' e' >> return ()

-- | 
-- Run the given event for ever.
--
runLoop :: Event a -> IO ()
runLoop e = do 
    e' <- prepare e
    runLoop' e'  
    where   
        runLoop' e = run' e >> threadDelay loopInterval >> runLoop' e
        loopInterval = 1000 * 5

-- | 
-- Run the given event until the first @Just x@  occurence, then return @x@.
--
runLoopUntil :: Event (Maybe a) -> IO a
runLoopUntil e = do 
    e' <- prepare e
    runLoop' e'  
    where   
        runLoop' e = do
            r <- run' e
            case (catMaybes r) of 
                []    -> threadDelay loopInterval >> runLoop' e
                (a:_) -> return a
        loopInterval = 1000 * 5


run' :: Event a -> IO [a]
run' ENever          = return []
run' (EMap f x)    = fmap (fmap f) (run' x)
run' (EPred p x)     = fmap (filter p) (run' x)
run' (EMerge a b)     = do
    a' <- run' a
    b' <- run' b
    return (a' ++ b')
run' (ESource i)     = i
run' (ESink o x)     = run' x >>= mapM o
run' (ESeq a b)      = run' a >> run' b

instance Functor (Event) where
    fmap    = EMap

instance Monoid (Event a) where
    mempty  = ENever
    mappend = EMerge

-- |
-- Map over occurances, semantically @map p xs@.
mapE :: (a -> b) -> Event a -> Event b
mapE = fmap

-- |
-- Filter occurances, semantically @filter p xs@.
filterE :: (a -> Bool) -> Event a -> Event a
filterE p = EPred p

-- |
-- Run both and behave as the second event, sematically @a `seq` b@.
sequenceE :: Event a -> Event b -> Event b
sequenceE = ESeq

-- |
-- The empty event, semantically @[]@.
neverE :: Event a
neverE = mempty

-- Always occur as the given value, semantically @repeat x@.
-- alwaysE :: a -> Event a
-- alwaysE = pure

-- |
-- Interleave occurences, semantically @merge xs ys@.
mergeE :: Event a -> Event a -> Event a
mergeE = mappend

-- -- Merge occurences using the given function, semantically @zipWith f xs ys@.
-- mergeWithE :: (a -> b -> c) -> Event a -> Event b -> Event c
-- mergeWithE = liftA2

-- |
-- Discard values of the event.
tickE :: Event a -> Event ()
tickE = tickME

-- |
-- Discard values, using an arbitrary empty element.
tickME :: Monoid b => Event a -> Event b
tickME = fmap (const mempty)




-- |
-- Event reading from external world.
--
-- The computation should be blocking and its values will be shared. 
--
-- This function can be used with standard I/O functions.
--
getE :: IO a -> Event a
getE k = unsafePerformIO $ do
    ch <- newChan
    forkIO $ cycleM $ 
        k >>= writeChan ch
    return (EChan ch)

-- |
-- Event reading from external world.
--
-- The computation should be non-blocking and its values will be contested.
--
-- This function should be used with /impure/ but /non-effectful/ functions such as @tryReadTMVar x@.
-- You should /not/ use this function with standard I/O functions as this
-- may lead to non-deterministic reads.
--
pollE :: IO (Maybe a) -> Event a
pollE = ESource . fmap maybeToList

-- Event interacting with the external world.
--
-- The computation should be non-blocking and its values will be contested.
--
-- modifyE :: (a -> IO b) -> Event a -> Event b
-- modifyE = ESink

-- |
-- Event writing to the external world.
--
putE :: (a -> IO ()) -> Event a -> Event a
putE k = ESink $ \x -> do
    k x
    return x

readChanE :: Chan a -> Event a
readChanE = EChan

writeChanE :: Chan a -> Event a -> Event a
writeChanE ch e = ESink (writeChan ch) e `sequenceE` e

getLineE :: Event String
getLineE = getE getLine 

putLineE :: Event String -> Event String
putLineE = putE putStrLn






-- ESource :: IO [a]       -> Event a
-- ESink   :: (a -> IO b)  -> Event a -> Event b

-- getVar :: TMVar a -> IO a
-- setVar :: TMVar a -> a -> IO a
-- run'   :: Event a -> IO [a]

-- modVar :: (a -> a) -> TMVar a -> IO ()               



-- IO a         from the state
-- IO [a]       from the event
--      => IO [a]    "recent history"




data Reactive a where
    RStep  :: TMVar a -> Event a -> Reactive a


runR  :: Reactive a -> IO a
runR (RStep x e) = atomically $ readTMVar x
-- TODO fold in event values...

stepper  :: a -> Event a -> Reactive a
stepper x e = RStep (unsafePerformIO $ newTMVarIO x) e

switcher :: Reactive a -> Event (Reactive a) -> Reactive a
switcher r e = join (stepper r e)

sample :: Reactive b -> Event a -> Event b
sample r e = ESource $ do
    e' <- run' e
    r' <- runR r
    case e' of
        [] -> return []
        _  -> return [r']


instance Monoid a => Monoid (Reactive a) where
    mempty  = pure mempty
    mappend = liftA2 mappend

instance Functor Reactive where
    fmap f = (pure f <*>)

instance Applicative Reactive where
    pure x = stepper x neverE 
    (RStep fv fe) <*> (RStep xv xe) = undefined

instance Monad Reactive where
    return = pure
    x >>= y = undefined



{-

sample   :: Event a -> Reactive b -> Event b







joinR    :: Reactive (Reactive a) -> Reactive a




modify   :: Event (a -> a) -> Reactive a -> Reactive a
set      :: Event a        -> Reactive a -> Reactive a
-}

















-- 
-- 
-- 
-- 
-- 
-- 
-- -- 
-- -- type MidiSource      = Midi.Source
-- -- type MidiDestination = Midi.Destination
-- -- 
-- -- midiInE :: MidiSource -> Event MidiMessage
-- -- midiInE = undefined
-- -- 
-- -- midiOutE :: MidiDestination -> Event MidiMessage -> Event MidiMessage
-- -- midiOutE = undefined
-- -- 
-- -- type OscMessage = OSC.Message
-- -- 
-- -- oscInE :: Int -> Event OscMessage
-- -- oscInE = undefined
-- -- 
-- -- oscOutE :: String -> Int -> Event OscMessage
-- -- oscOutE = undefined
-- 


guard :: (a -> Bool) -> (a -> Maybe a)
guard p x
    | p x       = Just x
    | otherwise = Nothing

list z f [] = z
list z f xs = f xs

filterMap p = catMaybes . map p   

cycleM x = x >> cycleM x 

single x = [x]

