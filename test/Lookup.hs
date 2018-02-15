
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE TypeSynonymInstances  #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE RankNTypes            #-}

module Lookup (tests) where

import Common

import qualified Data.Tree.AVL            as AVL

import qualified Debug.Trace as Debug

--
import           Test.Framework                       (Test, testGroup)
import           Test.Framework.Providers.QuickCheck2 (testProperty)
import           Test.QuickCheck                      ( Arbitrary (..)
                                                      , Gen
                                                      , Property
                                                      , (===)
                                                      , (==>) )
import           Test.QuickCheck.Instances  ()

tests :: [Test]
tests =
    [ testGroup "Lookup"
        [ testProperty "Generated proofs are verified" $
          \k list ->
            let
                tree                        = AVL.fromList list :: M
                scan @ ((search, proof), _) = AVL.lookup k tree
                proofIsGood                 = AVL.checkProof (tree^.AVL.rootHash) proof
                exists                      = lookup k (reverse list)
            in
                proofIsGood
            &&  search == exists
        ]
    ]