    
-- | All the building blocks to allow rules to produce outputs.
-- for example, you can display a message like this:
-- do
--    outputAll_ "hello, world!"

module Language.Nomyx.Outputs (
   OutputNumber,
   newOutput, newOutput_,
   outputAll, outputAll_,
   getOutput, getOutput_,
   updateOutput,
   delOutput,
   displayVar, displayVar',
   displaySimpleVar,
   displayArrayVar
   ) where

import Language.Nomyx.Expression
import Language.Nomyx.Variables
import Data.Typeable
import Control.Monad.State
import Control.Applicative


-- * Outputs

-- | outputs a message to one player
newOutput :: Maybe PlayerNumber -> NomexNE String -> Nomex OutputNumber
newOutput = NewOutput

-- | outputs a message to one player
newOutput_ :: Maybe PlayerNumber -> String -> Nomex OutputNumber
newOutput_ ns mpn = NewOutput ns (return mpn)

-- | output a message to all players
outputAll :: NomexNE String -> Nomex OutputNumber
outputAll = newOutput Nothing 

-- | output a constant message to all players
outputAll_ :: String -> Nomex ()
outputAll_ s = void $ newOutput Nothing (return s) 

-- | get an output by number
getOutput :: OutputNumber -> NomexNE (Maybe String)
getOutput = GetOutput

-- | get an output by number, partial version
getOutput_ :: OutputNumber -> Nomex String
getOutput_ on = partial "getOutput_ : Output number not existing" $ liftEffect $ getOutput on

-- | update an output
updateOutput :: OutputNumber -> NomexNE String -> Nomex Bool
updateOutput = UpdateOutput

-- | delete an output
delOutput :: OutputNumber -> Nomex Bool
delOutput = DelOutput
              
-- permanently display a variable
displayVar :: (Typeable a, Show a) => Maybe PlayerNumber  -> MsgVar a -> (Maybe a -> NomexNE String) -> Nomex OutputNumber
displayVar mpn mv dis = do
   on <- newOutput mpn $ readMsgVar mv >>= dis
   onMsgVarDelete mv (void $ delOutput on)
   return on


-- permanently display a variable
displayVar' :: (Typeable a, Show a) => Maybe PlayerNumber -> MsgVar a -> (a -> NomexNE String) -> Nomex OutputNumber
displayVar' mpn mv dis = displayVar mpn mv dis' where
   dis' Nothing  = return $ "Variable " ++ getMsgVarName mv ++ " deleted"
   dis' (Just a) = (++ "\n") <$> dis a
   
displaySimpleVar :: (Typeable a, Show a) => Maybe PlayerNumber -> MsgVar a -> String -> Nomex OutputNumber
displaySimpleVar mpn mv title = displayVar' mpn mv showVar where
   showVar a = return $ title ++ ": " ++ (show a) ++ "\n"

displayArrayVar :: (Typeable a, Show a, Typeable i, Show i) => Maybe PlayerNumber -> ArrayVar i a -> String -> Nomex OutputNumber
displayArrayVar mpn mv title = displayVar' mpn mv (showArrayVar title) where

showArrayVar :: (Typeable a, Show a, Typeable i, Show i) => String -> [(i, a)] -> NomexNE String
showArrayVar title l = return $ title ++ "\n" ++ concatMap (\(i,a) -> show i ++ "\t" ++ show a ++ "\n") l
