{-# LANGUAGE CPP #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeFamilies #-}
#if defined(__GLASGOW_HASKELL__) && __GLASGOW_HASKELL__ >= 702
{-# LANGUAGE Trustworthy #-}
#endif
-----------------------------------------------------------------------------
-- |
-- Module      :  Data.Profunctor.Composition
-- Copyright   :  (C) 2011-2014 Edward Kmett
-- License     :  BSD-style (see the file LICENSE)
--
-- Maintainer  :  Edward Kmett <ekmett@gmail.com>
-- Stability   :  provisional
-- Portability :  GADTs
--
----------------------------------------------------------------------------
module Data.Profunctor.Composition
  (
  -- * Profunctor Composition
    Procompose(..)
  , procomposed
  -- * Bicategorical Associators
  , idl
  , idr
  , assoc
  -- * Generalized Composition
  , upstars, kleislis
  , downstars, cokleislis
  ) where

import Control.Arrow
import Control.Category
import Control.Comonad
import Control.Monad (liftM)
import Data.Functor.Compose
import Data.Profunctor
import Data.Profunctor.Closed
import Data.Profunctor.Monad
import Data.Profunctor.Rep
import Data.Profunctor.Unsafe
import Prelude hiding ((.),id)

type Iso s t a b = forall p f. (Profunctor p, Functor f) => p a (f b) -> p s (f t)

-- * Profunctor Composition

-- | @'Procompose' p q@ is the 'Profunctor' composition of the
-- 'Profunctor's @p@ and @q@.
--
-- For a good explanation of 'Profunctor' composition in Haskell
-- see Dan Piponi's article:
--
-- <http://blog.sigfpe.com/2011/07/profunctors-in-haskell.html>
data Procompose p q d c where
  Procompose :: p x c -> q d x -> Procompose p q d c

instance Category p => ProfunctorMonad (Procompose p) where
  proreturn = Procompose id
  projoin (Procompose p (Procompose q r)) = Procompose (p . q) r

procomposed :: Category p => Procompose p p a b -> p a b
procomposed (Procompose pxc pdx) = pxc . pdx
{-# INLINE procomposed #-}

instance (Profunctor p, Profunctor q) => Profunctor (Procompose p q) where
  dimap l r (Procompose f g) = Procompose (rmap r f) (lmap l g)
  {-# INLINE dimap #-}
  lmap k (Procompose f g) = Procompose f (lmap k g)
  {-# INLINE rmap #-}
  rmap k (Procompose f g) = Procompose (rmap k f) g
  {-# INLINE lmap #-}
  k #. Procompose f g     = Procompose (k #. f) g
  {-# INLINE ( #. ) #-}
  Procompose f g .# k     = Procompose f (g .# k)
  {-# INLINE ( .# ) #-}

instance Profunctor p => Functor (Procompose p q a) where
  fmap k (Procompose f g) = Procompose (rmap k f) g
  {-# INLINE fmap #-}

-- | The composition of two 'Representable' 'Profunctor's is 'Representable' by
-- the composition of their representations.
instance (Representable p, Representable q) => Representable (Procompose p q) where
  type Rep (Procompose p q) = Compose (Rep q) (Rep p)
  tabulate f = Procompose (tabulate id) (tabulate (getCompose . f))
  {-# INLINE tabulate #-}
  rep (Procompose g f) d = Compose $ rep g <$> rep f d
  {-# INLINE rep #-}

instance (Corepresentable p, Corepresentable q) => Corepresentable (Procompose p q) where
  type Corep (Procompose p q) = Compose (Corep p) (Corep q)
  cotabulate f = Procompose (cotabulate (f . Compose)) (cotabulate id)
  {-# INLINE cotabulate #-}
  corep (Procompose g f) (Compose d) = corep g $ corep f <$> d
  {-# INLINE corep #-}

instance (Strong p, Strong q) => Strong (Procompose p q) where
  first' (Procompose x y) = Procompose (first' x) (first' y)
  {-# INLINE first' #-}
  second' (Procompose x y) = Procompose (second' x) (second' y)
  {-# INLINE second' #-}

instance (Choice p, Choice q) => Choice (Procompose p q) where
  left' (Procompose x y) = Procompose (left' x) (left' y)
  {-# INLINE left' #-}
  right' (Procompose x y) = Procompose (right' x) (right' y)
  {-# INLINE right' #-}

instance (Closed p, Closed q) => Closed (Procompose p q) where
  closed (Procompose x y) = Procompose (closed x) (closed y)
  {-# INLINE closed #-}

-- * Lax identity

-- | @(->)@ functions as a lax identity for 'Profunctor' composition.
--
-- This provides an 'Iso' for the @lens@ package that witnesses the
-- isomorphism between @'Procompose' (->) q d c@ and @q d c@, which
-- is the left identity law.
--
-- @
-- 'idl' :: 'Profunctor' q => Iso' ('Procompose' (->) q d c) (q d c)
-- @
idl :: Profunctor q => Iso (Procompose (->) q d c) (Procompose (->) r d' c') (q d c) (r d' c')
idl = dimap (\(Procompose g f) -> rmap g f) (fmap (Procompose id))

-- | @(->)@ functions as a lax identity for 'Profunctor' composition.
--
-- This provides an 'Iso' for the @lens@ package that witnesses the
-- isomorphism between @'Procompose' q (->) d c@ and @q d c@, which
-- is the right identity law.
--
-- @
-- 'idr' :: 'Profunctor' q => Iso' ('Procompose' q (->) d c) (q d c)
-- @
idr :: Profunctor q => Iso (Procompose q (->) d c) (Procompose r (->) d' c') (q d c) (r d' c')
idr = dimap (\(Procompose g f) -> lmap f g) (fmap (`Procompose` id))


-- | The associator for 'Profunctor' composition.
--
-- This provides an 'Iso' for the @lens@ package that witnesses the
-- isomorphism between @'Procompose' p ('Procompose' q r) a b@ and
-- @'Procompose' ('Procompose' p q) r a b@, which arises because
-- @Prof@ is only a bicategory, rather than a strict 2-category.
assoc :: Iso (Procompose p (Procompose q r) a b) (Procompose x (Procompose y z) a b)
             (Procompose (Procompose p q) r a b) (Procompose (Procompose x y) z a b)
assoc = dimap (\(Procompose f (Procompose g h)) -> Procompose (Procompose f g) h)
              (fmap (\(Procompose (Procompose f g) h) -> Procompose f (Procompose g h)))

-- | 'Profunctor' composition generalizes 'Functor' composition in two ways.
--
-- This is the first, which shows that @exists b. (a -> f b, b -> g c)@ is
-- isomorphic to @a -> f (g c)@.
--
-- @'upstars' :: 'Functor' f => Iso' ('Procompose' ('UpStar' f) ('UpStar' g) d c) ('UpStar' ('Compose' f g) d c)@
upstars :: Functor g
        => Iso (Procompose (UpStar f ) (UpStar g ) d  c )
               (Procompose (UpStar f') (UpStar g') d' c')
               (UpStar (Compose g  f ) d  c )
               (UpStar (Compose g' f') d' c')
upstars = dimap hither (fmap yon) where
  hither (Procompose (UpStar xgc) (UpStar dfx)) = UpStar (Compose . fmap xgc . dfx)
  yon (UpStar dfgc) = Procompose (UpStar id) (UpStar (getCompose . dfgc))

-- | 'Profunctor' composition generalizes 'Functor' composition in two ways.
--
-- This is the second, which shows that @exists b. (f a -> b, g b -> c)@ is
-- isomorphic to @g (f a) -> c@.
--
-- @'downstars' :: 'Functor' f => Iso' ('Procompose' ('DownStar' f) ('DownStar' g) d c) ('DownStar' ('Compose' g f) d c)@
downstars :: Functor f
          => Iso (Procompose (DownStar f ) (DownStar g ) d  c )
                 (Procompose (DownStar f') (DownStar g') d' c')
                 (DownStar (Compose f  g ) d  c )
                 (DownStar (Compose f' g') d' c')
downstars = dimap hither (fmap yon) where
  hither (Procompose (DownStar gxc) (DownStar fdx)) = DownStar (gxc . fmap fdx . getCompose)
  yon (DownStar dgfc) = Procompose (DownStar (dgfc . Compose)) (DownStar id)

-- | This is a variant on 'upstars' that uses 'Kleisli' instead of 'UpStar'.
--
-- @'kleislis' :: 'Monad' f => Iso' ('Procompose' ('Kleisli' f) ('Kleisli' g) d c) ('Kleisli' ('Compose' f g) d c)@
kleislis :: Monad g
        => Iso (Procompose (Kleisli f ) (Kleisli g ) d  c )
               (Procompose (Kleisli f') (Kleisli g') d' c')
               (Kleisli (Compose g  f ) d  c )
               (Kleisli (Compose g' f') d' c')
kleislis = dimap hither (fmap yon) where
  hither (Procompose (Kleisli xgc) (Kleisli dfx)) = Kleisli (Compose . liftM xgc . dfx)
  yon (Kleisli dfgc) = Procompose (Kleisli id) (Kleisli (getCompose . dfgc))

-- | This is a variant on 'downstars' that uses 'Cokleisli' instead
-- of 'DownStar'.
--
-- @'cokleislis' :: 'Functor' f => Iso' ('Procompose' ('Cokleisli' f) ('Cokleisli' g) d c) ('Cokleisli' ('Compose' g f) d c)@
cokleislis :: Functor f
          => Iso (Procompose (Cokleisli f ) (Cokleisli g ) d  c )
                 (Procompose (Cokleisli f') (Cokleisli g') d' c')
                 (Cokleisli (Compose f  g ) d  c )
                 (Cokleisli (Compose f' g') d' c')
cokleislis = dimap hither (fmap yon) where
  hither (Procompose (Cokleisli gxc) (Cokleisli fdx)) = Cokleisli (gxc . fmap fdx . getCompose)
  yon (Cokleisli dgfc) = Procompose (Cokleisli (dgfc . Compose)) (Cokleisli id)