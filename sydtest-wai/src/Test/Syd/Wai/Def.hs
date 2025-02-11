{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}

module Test.Syd.Wai.Def where

import GHC.Stack (HasCallStack)
import Network.HTTP.Client as HTTP
import Network.Socket (PortNumber)
import Network.Wai as Wai
import Network.Wai.Handler.Warp as Warp
import Test.Syd
import Test.Syd.Wai.Client

-- | Run a given 'Wai.Application' around every test.
--
-- This provides a 'WaiClient ()' which contains the port of the running application.
waiClientSpec :: Wai.Application -> TestDefM (HTTP.Manager ': outers) (WaiClient ()) result -> TestDefM outers oldInner result
waiClientSpec application = waiClientSpecWith $ pure application

-- | Run a given 'Wai.Application', as built by the given action, around every test.
waiClientSpecWith :: IO Application -> TestDefM (HTTP.Manager ': outers) (WaiClient ()) result -> TestDefM outers oldInner result
waiClientSpecWith application = waiClientSpecWithSetupFunc (\_ -> liftIO $ (,) <$> application <*> pure ())

-- | Run a given 'Wai.Application', as built by the given 'SetupFunc', around every test.
waiClientSpecWithSetupFunc ::
  (HTTP.Manager -> SetupFunc oldInner (Application, env)) ->
  TestDefM (HTTP.Manager ': outers) (WaiClient env) result ->
  TestDefM outers oldInner result
waiClientSpecWithSetupFunc setupFunc = managerSpec . waiClientSpecWithSetupFunc' setupFunc

-- | Run a given 'Wai.Application', as built by the given 'SetupFunc', around every test.
--
-- This function doesn't set up the 'HTTP.Manager' like 'waiClientSpecWithSetupFunc' does.
waiClientSpecWithSetupFunc' ::
  (HTTP.Manager -> SetupFunc oldInner (Application, env)) ->
  TestDefM (HTTP.Manager ': outers) (WaiClient env) result ->
  TestDefM (HTTP.Manager ': outers) oldInner result
waiClientSpecWithSetupFunc' setupFunc = setupAroundWith' (\man -> setupFunc man `connectSetupFunc` waiClientSetupFunc man)

-- | A 'SetupFunc' for a 'WaiClient', given an 'Application' and user-defined @env@.
waiClientSetupFunc :: HTTP.Manager -> SetupFunc (Application, env) (WaiClient env)
waiClientSetupFunc man = wrapSetupFunc $ \(application, env) -> do
  p <- unwrapSetupFunc applicationSetupFunc application
  let client =
        WaiClient
          { waiClientManager = man,
            waiClientEnv = env,
            waiClientPort = p
          }
  pure client

-- | Define a test in the 'WaiClientM site' monad instead of 'IO'.
--
-- Example usage:
--
-- > waiClientSpec exampleApplication $ do
-- >   describe "/" $ do
-- >     wit "works with a get" $
-- >       get "/" `shouldRespondWith` 200
-- >     wit "works with a post" $
-- >       post "/" `shouldRespondWith` ""
wit ::
  forall env e outers.
  ( HasCallStack,
    IsTest (WaiClient env -> IO e),
    Arg1 (WaiClient env -> IO e) ~ (),
    Arg2 (WaiClient env -> IO e) ~ WaiClient env
  ) =>
  String ->
  WaiClientM env e ->
  TestDefM outers (WaiClient env) ()
wit s f = it s ((\cenv -> runWaiClientM cenv f) :: WaiClient env -> IO e)

-- | Run a given 'Wai.Application' around every test.
--
-- This provides the port on which the application is running.
waiSpec :: Wai.Application -> TestDef outers PortNumber -> TestDef outers ()
waiSpec application = waiSpecWithSetupFunc $ pure application

-- | Run a 'Wai.Application' around every test by setting it up with the given setup function.
--
-- This provides the port on which the application is running.
waiSpecWith :: (forall r. (Application -> IO r) -> IO r) -> TestDef outers PortNumber -> TestDef outers ()
waiSpecWith appFunc = waiSpecWithSetupFunc $ makeSimpleSetupFunc appFunc

-- | Run a 'Wai.Application' around every test by setting it up with the given setup function that can take an argument.
-- a
-- This provides the port on which the application is running.
waiSpecWith' :: (forall r. (Application -> IO r) -> (a -> IO r)) -> TestDef outers PortNumber -> TestDef outers a
waiSpecWith' appFunc = waiSpecWithSetupFunc $ SetupFunc appFunc

-- | Run a 'Wai.Application' around every test by setting it up with the given 'SetupFunc'.
-- a
-- This provides the port on which the application is running.
waiSpecWithSetupFunc :: SetupFunc a Application -> TestDef outers PortNumber -> TestDef outers a
waiSpecWithSetupFunc setupFunc = setupAroundWith (setupFunc `connectSetupFunc` applicationSetupFunc)

-- | A 'SetupFunc' to run an application and provide its port.
applicationSetupFunc :: SetupFunc Application PortNumber
applicationSetupFunc = SetupFunc $ \func application ->
  Warp.testWithApplication (pure application) $ \p ->
    func (fromIntegral p) -- Hopefully safe, because 'testWithApplication' should give us sensible port numbers

-- | Create a 'HTTP.Manager' before all tests in the given group.
managerSpec :: TestDefM (HTTP.Manager ': outers) inner result -> TestDefM outers inner result
managerSpec = beforeAll $ HTTP.newManager HTTP.defaultManagerSettings
