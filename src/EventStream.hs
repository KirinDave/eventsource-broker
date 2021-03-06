{-# LANGUAGE OverloadedStrings #-}

{-
  See https://github.com/cdsmith/gloss-web

  Copyright (c)2011, Chris Smith <cdsmith@gmail.com>

  All rights reserved.

  Redistribution and use in source and binary forms, with or without
  modification, are permitted provided that the following conditions are met:

      * Redistributions of source code must retain the above copyright
        notice, this list of conditions and the following disclaimer.

      * Redistributions in binary form must reproduce the above
        copyright notice, this list of conditions and the following
        disclaimer in the documentation and/or other materials provided
        with the distribution.

      * Neither the name of Chris Smith <cdsmith@gmail.com> nor the names of other
        contributors may be used to endorse or promote products derived
        from this software without specific prior written permission.

  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
-}

{-|
    A Snap adapter to the HTML5 Server-Sent Events API.  Push-mode and
    pull-mode interfaces are both available.
-}
module EventStream (
    ServerEvent(..),
    eventStreamPull,
    eventStreamPush
    ) where

import Blaze.ByteString.Builder
import Blaze.ByteString.Builder.Char8
import Control.Monad.Trans
import Control.Concurrent
import Data.Monoid
import Data.Enumerator.List (generateM)
import Snap.Types

{-|
    Type representing a communication over an event stream.  This can be an
    actual event, a comment, a modification to the retry timer, or a special
    "close" event indicating the server should close the connection.
-}
data ServerEvent
    = ServerEvent {
        eventName :: Maybe Builder,
        eventId   :: Maybe Builder,
        eventData :: [Builder]
        }
    | CommentEvent {
        eventComment :: Builder
        }
    | RetryEvent {
        eventRetry :: Int
        }
    | CloseEvent


{-|
    Newline as a Builder.
-}
nl = fromChar '\n'


{-|
    Field names as Builder
-}
nameField = fromString "event:"
idField = fromString "id:"
dataField = fromString "data:"
retryField = fromString "retry:"
commentField = fromChar ':'


{-|
    Wraps the text as a labeled field of an event stream.
-}
field l b = l `mappend` b `mappend` nl


{-|
    Appends a buffer flush to the end of a Builder.
-}
flushAfter b = b `mappend` flush


{-|
    Converts a 'ServerEvent' to its wire representation as specified by the
    @text/event-stream@ content type.
-}
eventToBuilder :: ServerEvent -> Maybe Builder
eventToBuilder (CommentEvent txt) = Just $ flushAfter $ field commentField txt
eventToBuilder (RetryEvent   n)   = Just $ flushAfter $ field retryField (fromShow n)
eventToBuilder (CloseEvent)       = Nothing
eventToBuilder (ServerEvent n i d)= Just $ flushAfter $
    (name n $ evid i $ mconcat (map (field dataField) d)) `mappend` nl
  where
    name Nothing  = id
    name (Just n) = mappend (field nameField n)
    evid Nothing  = id
    evid (Just i) = mappend (field idField   i)


{-|
    Sets up this request to act as an event stream, obtaining its events from
    polling the given IO action.
-}
eventStreamPull :: IO ServerEvent -> Snap ()
eventStreamPull source = do
    modifyResponse (setContentType "text/event-stream")
    timeout <- getTimeoutAction
    modifyResponse $ setResponseBody $
        generateM (timeout 3600 >> fmap eventToBuilder source)


{-|
    Sets up this request to act as an event stream, returning an action to send
    events along the stream.
-}
eventStreamPush :: Snap (ServerEvent -> IO ())
eventStreamPush = do
    chan <- liftIO newChan
    eventStreamPull (readChan chan)
    return (writeChan chan)

