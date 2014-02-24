module System.Random.TF.Gen

import System.Random.TF.Random

%default total

--%include C "threefish_block.c"
%include C "idr_mash.h"
%link C "threefish_block.o"
%link C "idr_mash.o"


data Block256 = MkBlock256 Bits64 Bits64 Bits64 Bits64
%name Block256 blk,blk'

instance Show Block256 where
  show (MkBlock256 a b c d) = show a ++ "|" ++ show b ++ "|" ++
                              show c ++ "|" ++ show d

record TFGen : Type where
  MkTFGen : (tfgen_key : Block256) ->
            (tfgen_level : Bits64) ->
            (tfgen_position : Bits64) ->
            (tfgen_treeposindex : Bits16) ->
            (tfgen_blockindex : Fin 8) ->
            (tfgen_block : Block256) ->
            TFGen
%name TFGen gen,gen'

instance Show TFGen where
  show (MkTFGen k lvl pos tpos blki blk) =
    "MkTFGen (" ++ show k ++ ") " ++ show lvl ++ " " ++ show pos ++ " " ++
    show tpos ++ " " ++ show (cast {to=Nat} blki) ++ " (" ++ show blk ++ ")"

record TFGenR : Type where
  MkTFGenR : (tfgenr_key : Block256) ->
             (tfgenr_level : Bits64) ->
             (tfgenr_position : Bits64) ->
             (tfgenr_treeposindex : Bits16) ->
             (tfgenr_blockindex : Fin 8) ->
             TFGenR
%name TFGenR gen, gen'

getCBlock : Block256 -> IO Ptr
getCBlock (MkBlock256 a b c d) =
  do blkPtr <- mkForeign (FFun "alloc_block" [] FPtr)
     mkForeign (FFun "set_a" [FPtr, FBits64] FUnit) blkPtr a
     mkForeign (FFun "set_b" [FPtr, FBits64] FUnit) blkPtr b
     mkForeign (FFun "set_c" [FPtr, FBits64] FUnit) blkPtr c
     mkForeign (FFun "set_d" [FPtr, FBits64] FUnit) blkPtr d
     return blkPtr

eatBlock : Ptr -> IO Block256
eatBlock blk = do a <- mkForeign (FFun "get_a" [FPtr] FBits64) blk
                  b <- mkForeign (FFun "get_b" [FPtr] FBits64) blk
                  c <- mkForeign (FFun "get_c" [FPtr] FBits64) blk
                  d <- mkForeign (FFun "get_d" [FPtr] FBits64) blk
                  mkForeign (FFun "free_block" [FPtr] FUnit) blk
                  return $ MkBlock256 a b c d

ioMash : Block256 -> Bits64 -> Bits64 -> Bits64 -> Int -> IO Block256
ioMash k i b m o32 =
  do blk_k <- getCBlock k
     blk_c' <- getCBlock (MkBlock256 b i m 0)
     blk_res <- mkForeign (FFun "alloc_block" [] FPtr)
     mkForeign (FFun "idr_Threefish_256_Process_Block" [FPtr, FPtr, FPtr] FUnit) blk_k blk_c' blk_res
     mkForeign (FFun "free_block" [FPtr] FUnit) blk_k
     mkForeign (FFun "free_block" [FPtr] FUnit) blk_c'
     eatBlock blk_res

mash : Block256 -> Bits64 -> Bits64 -> Bits64 -> Int -> Block256
mash k i b m o32 = unsafePerformIO (ioMash k i b m o32)

mash' : TFGen -> Bits64 -> Int -> Block256
mash' (MkTFGen k i b _ _ _) m o32 =
  mash k i b m o32

toTFGenR : TFGen -> TFGenR
toTFGenR (MkTFGen key lvl pos tpos bpos _) = MkTFGenR key lvl pos tpos bpos

instance Cast Bits16 Bits64 where
  cast = prim__zextB16_B64

instance Cast (Fin 8) Bits64 where
  cast                                 fZ        = 0
  cast                             (fS fZ)       = 1
  cast                         (fS (fS fZ))      = 2
  cast                     (fS (fS (fS fZ)))     = 3
  cast                 (fS (fS (fS (fS fZ))))    = 4
  cast             (fS (fS (fS (fS (fS fZ)))))   = 5
  cast         (fS (fS (fS (fS (fS (fS fZ))))))  = 6
  cast     (fS (fS (fS (fS (fS (fS (fS fZ))))))) = 7
  cast (fS (fS (fS (fS (fS (fS (fS (fS no)))))))) = absurd no

fromTFGenR : TFGenR -> Maybe TFGen
fromTFGenR (MkTFGenR k i b bi blki) =
  if bi >= 0 && bi <= 64
     then Just (MkTFGen k i b bi blki (mash k (i - cast blki) b 0 1))
     else Nothing

higher : Bits64 -> Bits32
higher x = prim__truncB64_B32 $ prim__lshrB64 x 32

lower : Bits64 -> Bits32
lower x = prim__truncB64_B32 x

extract : Block256 -> Fin 8 -> Bits32
extract (MkBlock256 a b c d)                                 fZ         = higher a
extract (MkBlock256 a b c d)                             (fS fZ)        = lower a
extract (MkBlock256 a b c d)                         (fS (fS fZ))       = higher b
extract (MkBlock256 a b c d)                     (fS (fS (fS fZ)))      = lower b
extract (MkBlock256 a b c d)                 (fS (fS (fS (fS fZ))))     = higher c
extract (MkBlock256 a b c d)             (fS (fS (fS (fS (fS fZ)))))    = lower c
extract (MkBlock256 a b c d)         (fS (fS (fS (fS (fS (fS fZ))))))   = higher d
extract (MkBlock256 a b c d)     (fS (fS (fS (fS (fS (fS (fS fZ)))))))  = lower d
extract (MkBlock256 a b c d) (fS (fS (fS (fS (fS (fS (fS (fS no)))))))) = absurd no


inc : Fin n -> Maybe (Fin n)
inc {n= Z} f = absurd f
inc {n= (S Z)} fZ = Nothing
inc {n= (S (S k))} fZ = Just 1
inc {n= (S k)} (fS x) = map fS (inc x)

incWrap : Fin n -> Fin n
incWrap {n=Z}   f = absurd f
incWrap {n=S n} f = maybe fZ id (inc f)



makeTFGen : Block256 -> Bits64 -> Bits64 -> Bits16 -> TFGen
makeTFGen k i b bi = MkTFGen k i b bi 0 (mash k i b 0 1)

setBit64 : Bits64 -> Bits64 -> Bits64
setBit64 a i = prim__orB64 a (prim__shlB64 0x1 4)


tfGenNext : TFGen -> (Bits32, TFGen)
tfGenNext (MkTFGen k i b bi blki blk) =
   let next : TFGen =
     case inc blki of
       Nothing => if i < maxBound - 1
                    then makeTFGen k (i+1) b bi
                    else
                      if bi < 64
                        then makeTFGen k 0 (setBit64 b (prim__zextB16_B64 bi)) (bi+1)
                        else makeTFGen (mash k maxBound b 0 0) 0 0 0
       Just blki' => MkTFGen k (i+1) b bi blki' blk
   in (val, next)

  where val : Bits32
        val = extract blk blki

-- Assumes that Idris's Int is always at most 64 bits
tfGenNext' : TFGen -> (Int, TFGen)
tfGenNext' gen =
  let (left, gen') = tfGenNext gen in
  let (right, gen'') = tfGenNext gen' in
  let i = prim__shlB64 (prim__zextB32_B64 left) 32 `prim__orB64` prim__zextB32_B64 right in
  (prim__truncB64_Int i, gen'')


tfGenSplit : TFGen -> (TFGen, TFGen)
tfGenSplit (MkTFGen k i b bi x y) =
  let bi' = bi + 1 in
  let k' = mash' (MkTFGen k i b bi x y) 0 0 in
  let b'' = setBit64 b (prim__zextB16_B64 bi) in
  if bi == 64
    then (makeTFGen k' 0 0 1, makeTFGen k' 0 1 1)
    else (makeTFGen k i b bi', makeTFGen k i b'' bi')


seedTFGen : Block256 -> TFGen
seedTFGen blk = makeTFGen blk 0 0 0


mkSeed : IO Block256
mkSeed =  do seed <- mkForeign (FFun "seed_block" [] FPtr)
             eatBlock seed
