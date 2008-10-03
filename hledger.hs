#!/usr/bin/env runhaskell
{-|
hledger - a ledger-compatible text-based accounting tool.

Copyright (c) 2007-2008 Simon Michael <simon@joyful.com>
Released under GPL version 3 or later.

This is a minimal haskell clone of John Wiegley's ledger
<http://newartisans.com/software/ledger.html>.  hledger generates
simple ledger-compatible register & balance reports from a plain text
ledger file, and demonstrates a (naive) purely functional
implementation of ledger.

This module includes some helpers for working with your ledger in ghci. Examples:

> $ rm -f hledger.o
> $ ghci hledger.hs
> *Main> l <- myledger
> Ledger with 696 entries, 132 accounts
> *Main> putStr $ drawTree $ treemap show $ accountnametree l
> ...
> *Main> putStr $ showLedgerAccounts l 1
> ...
> *Main> printregister l
> ...
> *Main> accounts l
> ...
> *Main> accountnamed "expenses:food:groceries"
> Account expenses:food:groceries with 60 transactions

-}

module Main
where
import System
import qualified Data.Map as Map (lookup)

import Options
import Tests (hunit, quickcheck)
import Ledger
import Ledger.Parse (parseLedgerFile, parseError)
import Ledger.Utils hiding (test)


main :: IO ()
main = do
  (opts, (cmd:args)) <- getArgs >>= parseOptions
  let pats = parsePatternArgs args
  run cmd opts pats
    where run cmd opts pats
              | Help `elem` opts            = putStr usage
              | cmd `isPrefixOf` "selftest" = selftest opts pats
              | cmd `isPrefixOf` "print"    = print_   opts pats
              | cmd `isPrefixOf` "register" = register opts pats
              | cmd `isPrefixOf` "balance"  = balance  opts pats
              | otherwise                   = putStr usage

type Command = [Flag] -> (Regex,Regex) -> IO ()

selftest :: Command
selftest opts pats = do 
  hunit
  quickcheck
  return ()

print_ :: Command
print_ opts pats = parseLedgerAndDo opts pats printentries

register :: Command
register opts pats = parseLedgerAndDo opts pats printregister

balance :: Command
balance opts pats = parseLedgerAndDo opts pats printbalance
    where
      printbalance :: Ledger -> IO ()
      printbalance l = putStr $ showLedgerAccounts l depth
          where 
            showsubs = (ShowSubs `elem` opts)
            depth = case (pats, showsubs) of
                      -- when there are no account patterns and no -s, show
                      -- only to depth 1. (This was clearer when we used maybe.)
                      ((wildcard,_), False) -> 1
                      otherwise  -> 9999

-- | parse the user's specified ledger file and do some action with it
-- (or report a parse error). This function makes the whole thing go.
parseLedgerAndDo :: [Flag] -> (Regex,Regex) -> (Ledger -> IO ()) -> IO ()
parseLedgerAndDo opts pats cmd = do
    path <- ledgerFilePath opts
    parsed <- parseLedgerFile path
    case parsed of Left err -> parseError err
                   Right l -> cmd $ cacheLedger l pats

-- ghci helpers

-- | get a Ledger from the file your LEDGER environment variable points to
-- or (WARNING) an empty one if there was a problem.
myledger :: IO Ledger
myledger = do
  parsed <- ledgerFilePath [] >>= parseLedgerFile
  let ledgerfile = either (\_ -> RawLedger [] [] [] "") id parsed
  return $ cacheLedger ledgerfile (wildcard,wildcard)

-- | get a Ledger from the given file path
ledgerfromfile :: String -> IO Ledger
ledgerfromfile f = do
  parsed <- ledgerFilePath [File f] >>= parseLedgerFile
  let ledgerfile = either (\_ -> RawLedger [] [] [] "") id parsed
  return $ cacheLedger ledgerfile (wildcard,wildcard)

-- | get a named account from your ledger file
accountnamed :: AccountName -> IO Account
accountnamed a = myledger >>= (return . fromMaybe nullacct . Map.lookup a . accounts)

