-- Simple example demonstrating the API: parse a file, and print its definition table
module Main where
import System.Environment
import System.FilePath
import System.Exit
import System.IO
import Control.Arrow      hiding ((<+>))
import Control.Monad
import Debug.Trace
import Text.PrettyPrint.HughesPJ

import Language.C              -- simple API
import Language.C.Analysis     -- analysis API
import Language.C.System.GCC   -- preprocessor used

usageMsg :: String -> String
usageMsg prg = render $
  text "Usage:" <+> text prg <+> hsep (map text ["CPP_OPTIONS","input_file.c"]) $+$ 
  (nest 4 $
    text "Environment Variables" $+$
      (nest 4 $ 
         hsep [text "TRACE_EVENTS", text "trace definition events as they occur"]
      )
  )

main :: IO ()
main = do
    let usageErr = (hPutStrLn stderr (usageMsg "./ScanFile") >> exitWith (ExitFailure 1))
    args <- getArgs
    when (length args < 1) usageErr
    doTraceDecls <- liftM (("TRACE_EVENTS" `elem`). map fst) getEnvironment
    -- get cpp options and input file
    let (opts,c_file) = (init &&& last) args

    -- parse
    ast <- errorOnLeftM "Parse Error" $
      parseCFile (newGCC "gcc") Nothing opts c_file

    -- analyze
    (globals,warnings) <- errorOnLeft "Semantic Error" $ runTrav_ $ traversal doTraceDecls ast

    -- print
    mapM (hPutStrLn stderr . show) warnings
    print $ pretty $ filterGlobalDecls (fileOfInterest c_file . fileOfNode) globals

    where
    traversal False ast = analyseAST ast
    traversal True  ast = withExtDeclHandler (analyseAST ast) $ \ext_decl ->
                          trace (declTrace ext_decl) (return ())

    checkResult :: (Show a) => String -> (Either a b) -> IO b
    checkResult label = either (error . (label++) . show) return
    fileOfInterest c_file file_name = fileOfInterest' (splitExtensions c_file) (splitExtension file_name)
    fileOfInterest' (c_base,c_ext) (f_base,f_ext) | c_base /= f_base = False
                                                  | f_ext == ".h" && c_ext == ".c"  = False
                                                  | otherwise = True

errorOnLeft :: (Show a) => String -> (Either a b) -> IO b
errorOnLeft msg = either (error . ((msg ++ ": ")++).show) return
errorOnLeftM msg action = action >>= errorOnLeft msg

declTrace :: DeclEvent -> String
declTrace event = render $ case event of
                                TagEvent tag_def     -> (text ("Tag: " ++ show (sueRef tag_def)) <+> file tag_def)
                                DeclEvent ident_decl -> (text ("Decl: " ++ show (declIdent ident_decl)) <+> file ident_decl)
                                TypeDefEvent tydef   -> (text ("Typedef: " ++ show (identOfTypeDef tydef)) <+> file tydef)
                                AsmEvent block       -> (text $ "Assembler block")
    where
    file :: (CNode a) => a -> Doc
    file = text . show . posOfNode . nodeInfo
                                                  