{-# LANGUAGE RecordWildCards #-}

module Web.Server(server) where

import General.Code
import General.Web
import CmdLine.All
import Web.Response
import Control.Concurrent
import Control.Exception
import Network
import Network.HTTP
import Network.URI
import Network.Socket


server :: CmdLine -> IO ()
server q@Server{..} = withSocketsDo $ do
    stop <- httpServer port (talk q)
    putStrLn $ "Started Hoogle Server on port " ++ show port
    b <- hIsClosed stdin
    (if b then forever $ threadDelay maxBound else getChar >> return ()) `finally` stop


-- | Given a port and a handler, return an action to shutdown the server
httpServer :: Int -> (Request String -> IO (Response String)) -> IO (IO ())
httpServer port handler = do
    s <- listenOn $ PortNumber $ fromIntegral port
    forkIO $ forever $ do
        (sock,host) <- Network.Socket.accept s
        bracket
            (socketConnection "" sock)
            close
            (\strm -> do
                res <- receiveHTTP strm
                case res of
                    Left x -> do
                        putStrLn $ "Bad connection: " ++ show x
                        respondHTTP strm $ Response (4,0,0) "Bad Request" [] ("400 Bad Request: " ++ show x)
                    Right x -> do
                        putStrLn $ "Serving: " ++ unescapeURL (show $ rqURI x)
                        respondHTTP strm =<< handler x
            )
    return $ sClose s


talk :: CmdLine -> Request String -> IO (Response String)
talk Server{..} Request{rqURI=URI{uriPath=path,uriQuery=query}}
    | path `elem` ["/","/hoogle"] = do
        args <- cmdLineWeb $ parseHttpQueryArgs $ drop 1 query
        response "/res" args{databases=databases}
    | takeDirectory path == "/res" = do
        h <- openBinaryFile (resources </> takeFileName path) ReadMode
        src <- hGetContents h
        return $ Response (2,0,0) "OK" [Header HdrCacheControl "max-age=604800" {- 1 week -}] src
    | otherwise
        = return $ Response (4,0,4) "Not Found" [] $ "404 Not Found: " ++ show path
