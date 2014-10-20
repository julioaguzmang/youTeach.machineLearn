function [rbm_updated ...
   trainGoodnessAvg_exclWeightPenalty_approx ...
   validGoodnessAvg_exclWeightPenalty ...
   trainGoodnessesAvg_exclWeightPenalty_approx ...
   validGoodnessesAvg_exclWeightPenalty ...
   immedWeightChangeMemory_updated] = ...
   train_gradDesc(rbm, dataArgs_list, ...   
   trainNumEpochs = 1, trainBatchSize = false, ...   
   trainRandShuff = true, ...
   trainGoodnessApproxChunk_numBatches = 1, ...
   validGoodnessCalcInterval_numChunks = 1, ...
   learningRate_init = 1e-1, momentumRate_init = 9e-1, ...
   nesterovAccGrad = true, weightRegulArgs_list = {'L2' 0}, ...
   bestStop = true, immedWeightChangesMemory_init = [], ...
   plotLearningCurves = true, ...
   saveEvery_numMins = 3, saveFileName = 'ffNN_trained.mat')
   % zzzBORED = 'Z' - waiting for Octave's TIMER functionality
   
   rbm_updated = rbm;
   weightDimSizes = rbm.weightDimSizes;   
   if isempty(immedWeightChangesMemory_init)
      immedWeightChangesMemory_updated = ...
         zeros(weightDimSizes);
   else
      immedWeightChangesMemory_updated = ...
         immedWeightChangesMemory_init;
   endif
   trainGoodnessAvg_exclWeightPenalty_approx = ...
      validGoodnessAvg_exclWeightPenalty = 0;   
   trainGoodnessesAvg_exclWeightPenalty_approx = ...
      validGoodnessesAvg_exclWeightPenalty = [];
   
   % following section needs trimming down later on   
   setData = setTrainValidTestData(dataArgs_list, ...
      trainBatchSize, trainRandShuff);
   batchSize = setData.trainBatchSize;
   trainNumBatches = setData.trainNumBatches;
   trainBatchDim = setData.trainBatchDim;
   trainInput = setData.trainInput;
   trainTargetOutput = setData.trainTargetOutput;
   trainInput_batches = setData.trainInput_batches;
   trainTargetOutput_batches = ...
      setData.trainTargetOutput_batches;
   validInput = setData.validInput;
   validTargetOutput = setData.validTargetOutput;
   testInput = setData.testInput;
   testTargetOutput = setData.testTargetOutput;

   valid_provided = ~isempty(validInput);
   validProvided_n_bestStop = valid_provided && bestStop;
   if (valid_provided)
      validBatchDim = arrNumDims(validInput);
   endif
   if (validProvided_n_bestStop)
      ffNN_best = ffNN_updated;
      validCostAvg_exclWeightPenalty_best = Inf;
      toSaveBest = false;
   endif 
   
   test_provided = ~(isempty(testInput) ...
      || isempty(testTargetOutput));
   if (test_provided)
      testBatchDim = max(arrNumDims(testInput), ...
         arrNumDims(testTargetOutput));
   endif
   
   learningRate = learningRate_init;
   momentumRate = momentumRate_init;
       
   trainCostAvg_exclWeightPenalty_currChunk = ...
      trainAccuracyAvg_currChunk = ...
      chunk = chunk_inEpoch = batch_inChunk = 0;
   
   validCostCalcInterval_numBatches = ...
      validCostCalcInterval_numChunks ...
      * trainCostApproxChunk_numBatches;

   overview(ffNN_updated);      
fprintf('\n\nTRAIN FORWARD-FEEDING NEURAL NETWORK (METHOD: GRADIENT DESCENT):\n\n'); 
   fprintf('   DATA SETS:\n');
   fprintf('      Training: %i cases\n', ...
      size(trainTargetOutput, 1));
   if (valid_provided)
      fprintf('      Validation: %i cases\n', ...
         rows(validTargetOutput));      
   endif
   if (test_provided)
      fprintf('      Test: %i cases\n', ...
         rows(testTargetOutput));
   endif
   
   fprintf('\n   TRAINING SETTINGS:\n');
   fprintf('      Training Epochs: %i\n', trainNumEpochs); 
fprintf('      Training Batches per Epoch: %i batches of %i', ...
      trainNumBatches, batchSize);
   if (trainRandShuff)
      fprintf(', shuffled in each epoch\n')
   else
      fprintf('\n');
   endif
   fprintf('      Learning Rate: %g\n', learningRate);
   if (momentumRate)
      fprintf('      Momentum: %g', momentumRate);
      if (nesterovAccGrad)
fprintf(',   applying Nesterov Accelerated Gradient (NAG)\n');
      else
         fprintf('\n');
      endif
   endif

   fprintf('      Weight Penalty Methods & Parameters:\n');
   weightRegulFuncs = weightRegulArgs_list{1};
   weightRegulParams = weightRegulArgs_list{2};
   for (l = 1 : numTransforms)      
      if (l > 1)
         if (length(weightRegulFuncs) < l)
            weightRegulFuncs{l} = weightRegulFuncs{l - 1};
         endif        
         if (length(weightRegulParams) < l)
            weightRegulParams(l) = weightRegulParams(l - 1);
         endif
      endif      
      if strcmp(weightRegulFuncs{l}, ...
         const_MacKay_empBayes_str)         
         weightRegulParam_print = '';
      else
         weightRegulParam_print = ...
            sprintf(': penalty term = %g', ...
            weightRegulParams(l));
      endif      
      fprintf(cstrcat('         Layer #', sprintf('%i', l),': ', ...
         weightRegulFuncs{l}, weightRegulParam_print, '\n'));         
   endfor
   
   if (bestStop)
fprintf('      Model Selection by Best Validation Performance\n');
   endif
   fprintf('      Saving Results in "%s" on Working Directory every %i Minutes\n', ...
      saveFileName, saveEvery_numMins);
   fprintf('\n');
   fprintf('   TRAINING PROGRESS:\n');
% fprintf(cstrcat('      (pre-terminate by "', zzzBORED, '" key stroke)\n'));
fprintf('      Training Avg Cost (excl Weight Penalty) approx''d w/ each chunk of %i batches\n',
      trainCostApproxChunk_numBatches);
fprintf('      Validation Avg Cost (excl Weight Penalty) updated every %i batches\n', ...
      validCostCalcInterval_numBatches);
   if (costFuncType_isCrossEntropy)
fprintf('         (Est Avg Classification Accuracy %%s in brackets)\n');
   endif
   lastSaveTime = trainStartTime = time;
   
   for (epoch = 1 : trainNumEpochs)
      
      if (trainRandShuff) && (epoch > 1)
         train_reshuffled = setTrainValidTestData...
            ({trainInput trainTargetOutput 1.0}, ...
            batchSize, trainRandShuff);
         trainInput_batches = ...
            train_reshuffled.trainInput_batches;
         trainTargetOutput_batches = ...
            train_reshuffled.trainTargetOutput_batches;    
      endif
      
      for (batch = 1 : trainNumBatches)
         
         if (trainNumBatches > 1)
            trainInput_batch = arrSubsetHighestDim...
              (trainInput_batches, batch);
            trainTargetOutput_batch = ...
               arrSubsetHighestDim...
               (trainTargetOutput_batches, batch);
         else
            trainInput_batch = trainInput_batches;
            trainTargetOutput_batch = ...
               trainTargetOutput_batches;
         endif
           
         if (momentumRate)
   
            if (nesterovAccGrad)

               [trainCostAvg_exclWeightPenalty_currBatch ...
                  trainAccuracyAvg_currBatch] = ...
                  costAvg_exclWeightPenalty(ffNN_updated, ...
                  trainInput_batch, ...
                  trainTargetOutput_batch, ...
         targetOutputs_areClassIndcsColVecs_ofNumClasses, ...
                  trainBatchDim);
                  
               ffNN_temp = ffNN_updated;
               for (l = 1 : numTransforms)
                  w = ffNN_temp.weights{l};
                  ffNN_temp.weights{l} = w + momentumRate ...
                  * ffNN_immedWeightChangesMemory_updated{l};
               endfor               
               [weightGrads_temp, ~, ~, ~, ~, ~, ...
                  weightRegulParams] = fProp_bProp...
                  (ffNN_temp, trainInput_batch, ...
                  trainTargetOutput_batch, ...
         targetOutputs_areClassIndcsColVecs_ofNumClasses, ...
                  {weightRegulFuncs weightRegulParams});               
            
               for (l = 1 : numTransforms)
               ffNN_immedWeightChangesMemory_updated{l} = ...
                     momentumRate ...
                  * ffNN_immedWeightChangesMemory_updated{l} ...
                  - learningRate * weightGrads_temp{l};
                  w = ffNN_updated.weights{l};
                  ffNN_updated.weights{l} = w ...
                  + ffNN_immedWeightChangesMemory_updated{l};
               endfor    
   
            else
                  
               [weightGrads, ...
               trainCostAvg_exclWeightPenalty_currBatch, ...
                  ~, ~, trainAccuracyAvg_currBatch, ~, ...
                  weightRegulParams] = fProp_bProp...
                  (ffNN_updated, trainInput_batch, ...
                  trainTargetOutput_batch, ...
         targetOutputs_areClassIndcsColVecs_ofNumClasses, ...
                  {weightRegulFuncs weightRegulParams});      

               for (l = 1 : numTransforms)
               ffNN_immedWeightChangesMemory_updated{l} = ...
                     momentumRate ...
               * ffNN_immedWeightChangesMemory_updated{l} ...
                     - learningRate * weightGrads{l};
                  w = ffNN_updated.weights{l};
                  ffNN_updated.weights{l} = w ...
                  + ffNN_immedWeightChangesMemory_updated{l};
               endfor
         
            endif
      
         else 
      
            [weightGrads, ...
               trainCostAvg_exclWeightPenalty_currBatch, ...
               ~, ~, trainAccuracyAvg_currBatch, ~, ...
               weightRegulParams] = fProp_bProp...
               (ffNN_updated, trainInput_batch, ...
               trainTargetOutput_batch, ...
            targetOutputs_areClassIndcsColVecs_ofNumClasses, ...               
               {weightRegulFuncs weightRegulParams});            
            
            for (l = 1 : numTransforms)               
               ffNN_immedWeightChangesMemory_updated{l} = ...
                  - learningRate * weightGrads{l};
               w = ffNN_updated.weights{l};
               ffNN_updated.weights{l} = w ...
                  + ffNN_immedWeightChangesMemory_updated{l};
            endfor
            
         endif
         
         batch_inChunk++;         
         trainCostAvg_exclWeightPenalty_currChunk += ...
            (trainCostAvg_exclWeightPenalty_currBatch ...
            - trainCostAvg_exclWeightPenalty_currChunk) ...
            / batch_inChunk;
         trainAccuracyAvg_currChunk += ...
            (trainAccuracyAvg_currBatch ...
            - trainAccuracyAvg_currChunk) ...
            / batch_inChunk;
         if (costFuncType_isCrossEntropy)
            trainAccuracyAvg_text = sprintf...
               (' (%.3g%%)', 100 * ...
               trainAccuracyAvg_currChunk);
         endif
         
         if (batch_inChunk ==
            trainCostApproxChunk_numBatches) || ...
            (batch == trainNumBatches)
                        
            chunk_inEpoch++; chunk++;
         trainCostsAvg_exclWeightPenalty_approx(chunk) = ...
               trainCostAvg_exclWeightPenalty_currChunk;
               
            if (valid_provided && ((mod(batch, ...
               validCostCalcInterval_numBatches) == 0) || ...
               (batch == trainNumBatches)))
            
               [costAvg_valid validAccuracyAvg] = ...
                  costAvg_exclWeightPenalty(ffNN_updated, ...
                  validInput, validTargetOutput, ...
         targetOutputs_areClassIndcsColVecs_ofNumClasses, ...
                  validBatchDim);
               validCostAvg_exclWeightPenalty = ...
                  validCostsAvg_exclWeightPenalty(chunk) = ...
                  costAvg_valid;
               if (costFuncType_isCrossEntropy)
                  validAccuracyAvg_text = sprintf...
                     (' (%.3g%%)', 100 * validAccuracyAvg);
               endif               
               if (bestStop && ...
                  (validCostAvg_exclWeightPenalty ...
                  < validCostAvg_exclWeightPenalty_best))
                  ffNN_best = ffNN_updated;
                  validCostAvg_exclWeightPenalty_best = ...
                     validCostAvg_exclWeightPenalty;
                  validAccuracyAvg_best = validAccuracyAvg;
                  toSaveBest = true;
               endif
            
            else
            
               validCostsAvg_exclWeightPenalty(chunk) = NA;
               
            endif
            
            
            
            if (time > lastSaveTime + saveEvery_numMins * 60)
               if (validProvided_n_bestStop)
                  if (toSaveBest)
                     saveFile(ffNN_updated, saveFileName);
                     lastSaveTime = time;                  
                     toSaveBest = false;
                  endif
               else
                  saveFile(ffNN_updated, saveFileName);
                  lastSaveTime = time;
               endif
               
            endif            
            
            trainCurrTime = time;
            trainElapsedTime_numMins = ...
               (trainCurrTime - trainStartTime) / 60;
fprintf('\r      Epoch %i Batch %i: TRAIN %.3g%s, VALID %.3g%s, elapsed %.3gm      ', ...
               epoch, batch, ...
               trainCostAvg_exclWeightPenalty_currChunk, ...
               trainAccuracyAvg_text, ...
               validCostAvg_exclWeightPenalty, ...
               validAccuracyAvg_text, trainElapsedTime_numMins);
            
            if (plotLearningCurves)
               plotLearningCurves_ffNN...
                  (trainCostAvg_exclWeightPenalty_currChunk, ...
                  trainAccuracyAvg_text, ...
                  trainCostsAvg_exclWeightPenalty_approx, ...   
                  validCostAvg_exclWeightPenalty, ...
                  validAccuracyAvg_text, ...
                  validCostsAvg_exclWeightPenalty, ...  
                  chunk, trainCostApproxChunk_numBatches, ...
                  batchSize, trainElapsedTime_numMins);
            endif
               
            trainCostAvg_exclWeightPenalty_currChunk = ...
               trainAccuracyAvg_currChunk = batch_inChunk = 0;  
 
            if (batch == trainNumBatches)         
               chunk_inEpoch = 0;
            endif
 
         endif
         
      endfor
   
   endfor

fprintf('\n\n   RESULTS:   Training Finished w/ Following Avg Costs (excl Weight Penalty):\n');

   trainCostAvg_exclWeightPenalty_approx = ...
      trainCostsAvg_exclWeightPenalty_approx(end);
   fprintf('      Training (approx''d by last chunk): %.3g%s\n', ...
      trainCostAvg_exclWeightPenalty_approx, ...
      trainAccuracyAvg_text);
      
   if (valid_provided)
      if (bestStop)
         ffNN_updated = ffNN_best;
         validCostAvg_exclWeightPenalty = ...
            validCostAvg_exclWeightPenalty_best;
         validAccuracyAvg = validAccuracyAvg_best;
         if (costFuncType_isCrossEntropy)
            validAccuracyAvg_text = sprintf...
               (' (%.3g%%)', 100 * validAccuracyAvg);
         endif
      endif
      fprintf('      Validation: %.3g%s\n', ...
         validCostAvg_exclWeightPenalty, ...
         validAccuracyAvg_text);
   endif   
   
   if (test_provided)
      [testCostAvg_exclWeightPenalty testAccuracyAvg] = ...
         costAvg_exclWeightPenalty(ffNN_updated, ...
         testInput, testTargetOutput, ...
         targetOutputs_areClassIndcsColVecs_ofNumClasses, ...
         testBatchDim);
      if (costFuncType_isCrossEntropy)
         testAccuracyAvg_text = sprintf...
            (' (%.3g%%)', 100 * testAccuracyAvg);
      else
         testAccuracyAvg_text = '';
      endif
      fprintf('      Test: %.3g%s\n', ...
         testCostAvg_exclWeightPenalty, ...
         testAccuracyAvg_text);
   endif  

   fprintf('\n');
   
   saveFile(ffNN_updated, saveFileName);
   
endfunction