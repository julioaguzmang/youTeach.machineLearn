function f = arrOpAcrossDim(Arr, op, op_vec = [], opDim = 1)

   % PERMUTE ARRAY SO THAT OPDIM = 1
   % -------------------------------
   numDims = arrNumDims(Arr);
   perm_vec = 1 : numDims;

   if (opDim > 1)
      perm_vec(1) = opDim;
      perm_vec(opDim) = 1;
   endif
      
   Arr_perm = arrPerm(Arr, perm_vec);   
   dimSzs_perm = arrDimSizes(Arr_perm);
   
   switch (op)
   
      case ('subset')
         dimSzs_perm(1) = length(op_vec);
         f_perm = reshape(Arr_perm(op_vec,:)(:), ...
            dimSzs_perm);

      case ('shuffle')
         f_perm = reshape(Arr_perm...
            (randperm(dimSzs_perm(1)),:)(:), ...
            dimSzs_perm);

      case ('split')        
         reshape_vec = dimSzs_perm;
         reshape_vec(1) = op_vec(1);
         reshape_vec(numDims + 1) = ...
            floor(dimSzs_perm(1) / op_vec(1));
         dimSzs_perm(1) = ...
            reshape_vec(numDims + 1) * reshape_vec(1);
         Arr_perm = reshape(Arr_perm...
            (1 : dimSzs_perm(1),:)(:), dimSzs_perm);
         splitPerm_vec = [(2 : numDims) 1];
         Arr_permForSplit = ...
            arrPerm(Arr_perm, splitPerm_vec);
         splitPerm_vec(numDims + 1) = numDims + 1;         
         reshape_vec_reorderedForSplit = ...
            reshape_vec(splitPerm_vec);
         f_permAfterSplit = ...
            reshape(Arr_permForSplit(:), ...
            reshape_vec_reorderedForSplit); 
         f_perm = ...
            arrIPerm(f_permAfterSplit, splitPerm_vec);
         perm_vec(numDims + 1) = numDims + 1;

   endswitch

   f = arrIPerm(f_perm, perm_vec);

end