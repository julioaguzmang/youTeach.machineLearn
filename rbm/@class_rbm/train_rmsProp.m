function [ffNN_updated ...
   trainCostAvg_exclWeightPenalty_approx ...
   validCostAvg_exclWeightPenalty ...
   testCostAvg_exclWeightPenalty ...
   trainCostsAvg_exclWeightPenalty_approx ...
   validCostsAvg_exclWeightPenalty ...
   ffNN_immedWeightChangesMemory_updated ...
   ffNN_avgWeightGradsSq_updated] = ...
   train_rmsProp(rbm, dataArgs_list, ...
   targetOutputs_areClassIndcsColVecs_ofNumClasses = false, ...
   trainNumEpochs = 1, trainBatchSize = false, ...   
   trainRandShuff = true, ...
   trainCostApproxChunk_numBatches = 1, ...
   validCostCalcInterval_numChunks = 1, ...
   stepRate_init = 1, decayRate_init = 9e-1, ...
   momentumRate_init = 9e-1, nesterovAccGrad = true, ...
   weightRegulArgs_list = {{'L2'} [0]}, bestStop = true, ...
   ffNN_immedWeightChangesMemory_init = {}, ...
   ffNN_avgWeightGradsSq_init = {}, ...
   plotLearningCurves = true, batchDim = 3, ...
   saveEvery_numMins = 3, saveFileName = 'ffNN_trained.mat', ...
   stepRate_adaptDownUp = [0.5 1.2], ...
   stepRate_range = [1e-6 50])
   % zzzBORED = 'Z' - waiting for Octave's TIMER functionality
   
   ffNN_updated = ffNN;
   numTransforms = ffNN_updated.numTransforms;
   weightDimSizes = ffNN.weightDimSizes;
   numTargets = columns(weightDimSizes{numTransforms});
   costFuncType = ffNN.costFuncType;
   costFuncType_isCrossEntropy = ...
      strcmp(costFuncType, 'CE-L') || ...
      strcmp(costFuncType, 'CE-S');
   
   zeros_ffNN_weightDimSizes = ...
      zeros_weightDimSizes(ffNN_updated);
   
   if isempty(ffNN_immedWeightChangesMemory_init)
      ffNN_immedWeightChangesMemory_updated = ...      
         zeros_ffNN_weightDimSizes;
      %ffNN_immedWeightChangeSignsMemory_updated = ...
   else
      ffNN_immedWeightChangesMemory_updated = ...
         ffNN_immedWeightChangesMemory_init;
      %for (l = 1 : numTransforms)
      %   ffNN_immedWeightChangeSignsMemory_updated{l} = ...
      %      sign(ffNN_immedWeightChangesMemory_updated{l});
      %endfor
   endif
   
   if isempty(ffNN_avgWeightGradsSq_init)
      ffNN_avgWeightGradsSq_updated = ...
         zeros_ffNN_weightDimSizes;
      ffNN_avgWeightGradsSq_startAtZero...
         (1 : numTransforms) = true;
   else
      ffNN_avgWeightGradsSq_updated = ...
         ffNN_avgWeightGradsSq_init;
      ffNN_avgWeightGradsSq_startAtZero...
         (1 : numTransforms) = false;
   endif   
   
   trainCostAvg_exclWeightPenalty_approx = ...
      validCostAvg_exclWeightPenalty = ...
      testCostAvg_exclWeightPenalty = 0;
   trainAccuracyAvg_text = validAccuracyAvg_text = '';
   trainCostsAvg_exclWeightPenalty_approx = ...
      validCostsAvg_exclWeightPenalty = [];
   
   % following section needs trimming down later on   
   setData = setTrainValidTestData(dataArgs_list, ...
      trainBatchSize, trainRandShuff);
   batchSize = setData.trainBatchSize;
   trainNumBatches = setData.trainNumBatches;
   trainBatchDim = setData.trainBatchDim;
   trainInput = setData.trainInput;
   trainInput_batches = setData.trainInput_batches;
   validInput = setData.validInput;


   valid_provided = ~(isempty(validInput) ...
      || isempty(validTargetOutput));
   validProvided_n_bestStop = valid_provided && bestStop;
   if (valid_provided)
      validBatchDim = max(arrNumDims(validInput), ...
         arrNumDims(validTargetOutput));
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
   
   stepRate = stepRate_init;   
   %for (l = 1 : numTransforms)
   %   ones_Arr = ones(weightDimSizes{l});
   %   stepRate_adaptMultiples_ones{l} = ones_Arr;
   %   stepRates{l} = stepRate * ones_Arr;
   %endfor
   %stepRate_adaptDown = stepRate_adaptDownUp(1);
   %stepRate_adaptUp = stepRate_adaptDownUp(2);   
   %stepRate_min = stepRate_range(1);
   %stepRate_max = stepRate_range(2);
   decayRate = decayRate_init;
   momentumRate = momentumRate_init;
       
   trainCostAvg_exclWeightPenalty_currChunk = ...
      trainAccuracyAvg_currChunk = ...
      chunk = chunk_inEpoch = batch_inChunk = 0;
   
   validCostCalcInterval_numBatches = ...
      validCostCalcInterval_numChunks ...
      * trainCostApproxChunk_numBatches;
    
   overview(ffNN_updated);
fprintf('\n\nTRAIN FORWARD-FEEDING NEURAL NETWORK (METHOD: RMSPROP):\n\n');
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
   fprintf('      Step Rate: %g\n', stepRate);
   % 'adapt x%s, range %s'
   % mat2str(stepRate_adaptDownUp), mat2str(stepRate_range));
   fprintf('      RMS Decay Rate: %g\n', decayRate);   
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
                  
                  if (ffNN_avgWeightGradsSq_startAtZero(l))
                     ffNN_avgWeightGradsSq_updated{l} = ...
                        weightGrads_temp{l} .^ 2;
                     ffNN_avgWeightGradsSq_startAtZero(l) = ...
                        false;
                  else
                     ffNN_avgWeightGradsSq_updated{l} = ...
                        decayRate ...
                        * ffNN_avgWeightGradsSq_updated{l} ...
                        + (1 - decayRate) ...
                        * (weightGrads_temp{l} .^ 2);
                  endif
               
               ffNN_immedWeightChangesMemory_updated{l} = ...
                     - stepRate .* ...
                     div0(weightGrads_temp{l}, ...
                     sqrt(ffNN_avgWeightGradsSq_updated{l}));
                  % 0 * momentumRate ...
                  % * ffNN_immedWeightChangesMemory_updated{l} ...   
                  % Geoffrey Hinton: standard momentum does not
                  % seem to help as much as expected -> need
                  % additional investigation. Hence we are
                  % multiplying the first term with 0 for now.
                  w = ffNN_updated.weights{l};
                  ffNN_updated.weights{l} = w ...
                  + ffNN_immedWeightChangesMemory_updated{l};   
            
                  %ffNN_immedWeightChangeSignsMemory_prev = ...
                  %ffNN_immedWeightChangeSignsMemory_updated{l};
            %ffNN_immedWeightChangeSignsMemory_updated{l} = ...
               %sign(ffNN_immedWeightChangesMemory_updated{l});
                  %signMatches = ...
               %ffNN_immedWeightChangeSignsMemory_updated{l} ...
                     %.* ffNN_immedWeightChangeSignsMemory_prev;
                  
                  %Adapting step rates by naively comparing 2
                  %gradients' signs does not seem to help,
                  %maybe because it's only suitable for
                  %full-batch RPROP, but not RMSPROP. Need
                  %more investigation.
                  
                  %stepRate_adaptMultiples = ...
                  %   stepRate_adaptMultiples_ones{l};
                  %stepRate_adaptMultiples...
                  %   (signMatches < 0) = stepRate_adaptDown;
                  %stepRate_adaptMultiples...
                  %   (signMatches > 0) = stepRate_adaptUp;                  
                  %stepRates{l} = min(max...
                  %   (stepRate_adaptMultiples ...
                  %   .* stepRates{l}, stepRate_min), ...
                  %   stepRate_max);
                  
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
               
                  if (ffNN_avgWeightGradsSq_startAtZero(l))
                     ffNN_avgWeightGradsSq_updated{l} = ...
                        weightGrads{l} .^ 2;
                     ffNN_avgWeightGradsSq_startAtZero(l) = ...
                        false;
                  else               
                     ffNN_avgWeightGradsSq_updated{l} = ...
                        decayRate ...
                        * ffNN_avgWeightGradsSq_updated{l} ...
                        + (1 - decayRate) ...
                        * (weightGrads{l} .^ 2);
                  endif
                                              
               ffNN_immedWeightChangesMemory_updated{l} = ...                   
                     momentumRate ...
               * ffNN_immedWeightChangesMemory_updated{l} ...
                     - stepRate .* div0(weightGrads{l}, ...
                     sqrt(ffNN_avgWeightGradsSq_updated{l}));
                                    
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
            
               if (ffNN_avgWeightGradsSq_startAtZero(l))
                  ffNN_avgWeightGradsSq_updated{l} = ...
                     weightGrads{l} .^ 2;
                  ffNN_avgWeightGradsSq_startAtZero(l) = ...
                     false;
               else
                  ffNN_avgWeightGradsSq_updated{l} = ...
                     decayRate ...
                     * ffNN_avgWeightGradsSq_updated{l} ...
                     + (1 - decayRate) ...
                     * (weightGrads{l} .^ 2);
               endif
   
               ffNN_immedWeightChangesMemory_updated{l} = ...
                  - stepRate .* div0(weightGrads{l}, ...
                  sqrt(ffNN_avgWeightGradsSq_updated{l}));
                  
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
         
         if (batch_inChunk == ...
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