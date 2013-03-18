
module Music.Imitator where

{-
    GUI:
    
        * Window
            * Button: Prepare
            * Button: Start
            * Button: Pause
            
            * Slider: Position
            * Text: Section, Bar

-}

import Data.Maybe
import Data.Either
import Data.Monoid  
import Control.Monad
import Control.Applicative

import Music.Imitator.Reactive
import Music.Imitator.Reactive.Midi
import Music.Imitator.Reactive.Osc
import Music.Imitator.Sound hiding (pulse)
import Music.Imitator.Util

import Music.Imitator.Util

{-
-- score = []

rotateMouse :: UGen -> UGen
rotateMouse gen =
    decode kNumSpeakers 
        $ foaRotate ((fst mouse + 1) * tau + (tau/8)) 
        $ foaPanB 0 0 
        $ gen
-}



-- type Time     = Double
type Duration = Time
type Envelope = Double -> Double
type Angle    = Double

data Transformation
    = Rotate Angle
    | Push
    -- TODO envelope
    -- TODO ATK rotation etc

data Command
    = StartRecord
        -- begin filling buffer from time 0
    | PauseRecord
        -- pause recording
    | ResumeRecord
        -- resume from paused position
    | StopRecord
        -- stop recording                      
    | ReadBuffer FilePath
        -- read input from given file
    | Play  Time Duration Transformation
        -- Play t d e
        -- Plays from time t to time t+d, using the given transformation


{-


runCommand :: Command -> IO ()
runCommand = undefined

runImitator :: [(Time, Command)] -> IO ()
runImitator []     = return ()
runImitator ((t,x):xs) = do
    -- usleep (round t*1000000)
    -- TODO cross-platform
    runCommand x
    runImitator xs

                                -}
