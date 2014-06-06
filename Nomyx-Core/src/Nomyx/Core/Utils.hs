-----------------------------------------------------------------------------
--
-- Module      :  Utils
-- Copyright   :
-- License     :  AllRightsReserved
--
-- Maintainer  :
-- Stability   :
-- Portability :
--
-- |
--
-----------------------------------------------------------------------------

{-# LANGUAGE CPP #-}

module Nomyx.Core.Utils where



import Codec.Archive.Tar as Tar
import System.IO.Temp
import System.Directory
import System.FilePath
#ifndef WINDOWS
import qualified System.Posix.Signals as S
#endif
import System.IO
import System.IO.PlafCompat
import Data.Lens
import Data.Maybe
import Control.Monad.State
import Control.Exception
import Control.Concurrent
import Control.Category ((>>>))
import Control.Monad.Catch as MC
import Nomyx.Core.Types
import Nomyx.Core.Engine

saveFile, profilesDir, uploadDir, tarFile :: FilePath
saveFile    = "Nomyx.save"
profilesDir = "profiles"
uploadDir   = "uploads"
testDir     = "test"
tarFile     = "Nomyx.tar"
   
-- | this function will return just a if it can cast it to an a.
maybeRead :: Read a => String -> Maybe a
maybeRead = fmap fst . listToMaybe . reads

-- | Replaces all instances of a value in a list by another value.
replace :: Eq a => a   -- ^ Value to search
        -> a   -- ^ Value to replace it with
        -> [a] -- ^ Input list
        -> [a] -- ^ Output list
replace x y = map (\z -> if z == x then y else z)

-- | generic function to say things on transformers like GameState, ServerState etc.
say :: String -> StateT a IO ()
say = lift . putStrLn

nomyxURL :: Network -> String
nomyxURL (Network host port) = "http://" ++ host ++ ":" ++ show port

getSaveFile :: Settings -> FilePath
getSaveFile set = _saveDir set </> saveFile

makeTar :: FilePath -> IO ()
makeTar saveDir = do
   putStrLn $ "creating tar in " ++ show saveDir
   Tar.create (saveDir </> tarFile) saveDir [saveFile, uploadDir]

untar :: FilePath -> IO FilePath
untar fp = do
   dir <- createTempDirectory "/tmp" "Nomyx"
   extract dir fp
   return dir

getUploadedModules :: FilePath -> IO [FilePath]
getUploadedModules saveDir = do
   mods <- getDirectoryContents $ saveDir </> uploadDir
   getRegularFiles (saveDir </> uploadDir) mods

getRegularFiles :: FilePath -> [FilePath] -> IO [FilePath]
getRegularFiles dir fps = filterM (getFileStatus . (\f -> dir </> f) >=> return . isRegularFile) fps

-- The setMode function is only used during module loading. In Windows,
-- a copied file automatically inherits permissions based on the containing
-- folder's ACLs an the user account being used.
#ifdef WINDOWS

setMode :: FilePath -> IO()
setMode _ = return ()

#else

setMode :: FilePath -> IO()
setMode file = setFileMode file (ownerModes + groupModes)

#endif

#ifdef WINDOWS

--no signals under windows
protectHandlers :: IO a -> IO a
protectHandlers = id

#else

installHandler' :: S.Handler -> S.Signal -> IO S.Handler
installHandler' handler signal = S.installHandler signal handler Nothing

signals :: [S.Signal]
signals = [ S.sigQUIT
          , S.sigINT
          , S.sigHUP
          , S.sigTERM
          ]

saveHandlers :: IO [S.Handler]
saveHandlers = liftIO $ mapM (installHandler' S.Ignore) signals

restoreHandlers :: [S.Handler] -> IO [S.Handler]
restoreHandlers h  = liftIO . sequence $ zipWith installHandler' h signals

protectHandlers :: IO a -> IO a
protectHandlers a = MC.bracket saveHandlers restoreHandlers $ const a

#endif

--Sets a watchdog to kill the evaluation thread if it doesn't finishes.
-- The function starts both the evaluation thread and the watchdog thread, and blocks awaiting the result.
-- Option 1: the evaluation thread finishes before the watchdog. The MVar is filled with the result,
--  which unblocks the main thread. The watchdog then finishes latter, and fills the MVar with Nothing.
-- Option 2: the watchdog finishes before the evaluation thread. The eval thread is killed, and the
--  MVar is filled with Nothing, which unblocks the main thread. The watchdog finishes.
evalWithWatchdog :: Show b => a -> (a -> IO b) -> IO (Maybe b)
evalWithWatchdog s f = do
   mvar <- newEmptyMVar
   hSetBuffering stdout NoBuffering
   --start evaluation thread
   id <- forkOS $ do
      s' <- f s
      s'' <- evaluate s'
      writeFile nullFileName $ show s''
      putMVar mvar (Just s'')
   --start watchdog thread
   forkIO $ watchDog 3 id mvar
   takeMVar mvar

-- | Fork off a thread which will sleep and then kill off the specified thread.
watchDog :: Int -> ThreadId -> MVar (Maybe a) -> IO ()
watchDog tout tid mvar = do
   threadDelay (tout * 1000000)
   killThread tid
   putMVar mvar Nothing

gameNameLens :: Lens GameInfo GameName
gameNameLens = loggedGame >>> game >>> gameName


