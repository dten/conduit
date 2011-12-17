{-# LANGUAGE FlexibleContexts #-}
module Data.Conduit.Zlib (
    -- * Conduits
    compress, decompress, gzip, ungzip,
    -- * Re-exported from zlib-bindings
    WindowBits (..), defaultWindowBits
) where

import Codec.Zlib
import Data.Conduit
import Data.ByteString (ByteString)
import qualified Data.ByteString as S
import Control.Monad.Trans.Resource
import Control.Monad.Trans.Class

-- | Gzip compression with default parameters.
gzip :: ResourceUnsafeIO m => ConduitM ByteString m ByteString
gzip = compress 1 (WindowBits 31)

-- | Gzip decompression with default parameters.
ungzip :: ResourceUnsafeIO m => ConduitM ByteString m ByteString
ungzip = decompress (WindowBits 31)

-- |
-- Decompress (inflate) a stream of 'ByteString's. For example:
--
-- >    run $ enumFile "test.z" $$ decompress defaultWindowBits $$ printChunks True

decompress
    :: ResourceUnsafeIO m
    => WindowBits -- ^ Zlib parameter (see the zlib-bindings package as well as the zlib C library)
    -> ConduitM ByteString m ByteString
decompress config = conduitM
    (lift $ unsafeFromIO $ initInflate config)
    (const $ return ())
    (push id)
    (close id)
  where
    push front _ [] = return $ ConduitResult StreamOpen [] $ front []
    push front inf (x:xs) = do
        chunks <- lift $ unsafeFromIO $ withInflateInput inf x callback
        push (front . (chunks ++)) inf xs
    close front inf (x:xs) = do
        chunks <- lift $ unsafeFromIO $ withInflateInput inf x callback
        close (front . (chunks ++)) inf xs
    close front inf [] = do
        chunk <- lift $ unsafeFromIO $ finishInflate inf
        return $ ConduitCloseResult [] $ front $ if S.null chunk then [] else [chunk]

-- |
-- Compress (deflate) a stream of 'ByteString's. The 'WindowBits' also control
-- the format (zlib vs. gzip).

compress
    :: ResourceUnsafeIO m
    => Int         -- ^ Compression level
    -> WindowBits  -- ^ Zlib parameter (see the zlib-bindings package as well as the zlib C library)
    -> ConduitM ByteString m ByteString
compress level config = conduitM
    (lift $ unsafeFromIO $ initDeflate level config)
    (const $ return ())
    (push id)
    (close id)
  where
    push front _ [] = return $ ConduitResult StreamOpen [] $ front []
    push front def (x:xs) = do
        chunks <- lift $ unsafeFromIO $ withDeflateInput def x callback
        push (front . (chunks ++)) def xs
    close front def (x:xs) = do
        chunks <- lift $ unsafeFromIO $ withDeflateInput def x callback
        close (front . (chunks ++)) def xs
    close front def [] = do
        chunks <- lift $ unsafeFromIO $ finishDeflate def callback
        return $ ConduitCloseResult [] $ front chunks

callback :: Monad m => m (Maybe a) -> m [a]
callback pop = go id where
    go front = do
       x <- pop
       case x of
           Nothing -> return $ front []
           Just y -> go (front . (:) y)
