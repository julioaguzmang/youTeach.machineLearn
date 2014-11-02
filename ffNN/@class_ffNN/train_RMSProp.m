function [ffNN_avgWeights ...
   trainCostAvg_exclWeightPenalty_approx ...
   validCostAvg_exclWeightPenalty ...
   testCostAvg_exclWeightPenalty ...
   trainCostsAvg_exclWeightPenalty_approx ...
   validCostsAvg_exclWeightPenalty ...   
   immedWeightChangesMemory avgWeightGradsSq] = ...
   train_rmsProp(ffNN_init, dataArgs_list, ...
   targetOutputs_areClassIndcsColVecs_ofNumClasses = false, ...
   trainNumEpochs = 1, trainBatchSize = false, ...   
   trainRandShuff = true, ...
   trainCostApproxChunk_numBatches = 1, ...
   validCostCalcInterval_numChunks = 1, ...
   stepRate_init = 1, decayRate_init = 9e-1, ...
   momentumRate_init = 9e-1, nesterovAccGrad = true, ...
   weightRegulArgs_list = {{'L2'} [0]}, ...
   connectProbs = [1.0], bestStop = true, ...
   saveFileName = 'ffNN_trained.mat', ...
   saveEvery_numMins = 3, plotLearningCurves = true, ...
   batchDim = 3, immedWeightChangesMemory_init = {}, ...
   avgWeightGradsSq_init = {}, ...   
   stepRate_adaptDownUp = [0.5 1.2], ...
   stepRate_range = [1e-6 50])
   % zzzBORED = 'Z' - waiting for Octave's TIMER functionality
   
   ffNN = ffNN_init;
   ffNN_avgWeights = avgWeights_byConnectProbs...
      (ffNN, connectProbs);
   numTransforms = ffNN.numTransforms;
   weightDimSizes = ffNN.weightDimSizes;
   numTargets = columns(weightDimSizes{numTransforms});
   costFuncType = ffNN.costFuncType;
   costFuncType_isCrossEntropy = ...
      strcmp(costFuncType, 'CE-L') || ...
      strcmp(costFuncType, 'CE-S');
   
   zeros_ffNN_weightDimSizes = zeros_weightDimSizes(ffNN);
   
   if isempty(immedWeightChangesMemory_init)
      immedWeightChangesMemory = zeros_ffNN_weightDimSizes;
      %ffNN_immedWeightChangeSignsMemory_updated = ...
   else
      immedWeightChangesMemory = immedWeightChangesMemory_init;
      %for (l = 1 : numTransforms)
      %   ffNN_immedWeightChangeSignsMemory_updated{l} = ...
      %      sign(ffNN_immedWeightChangesMemory_updated{l});
      %endfor
   endif
   
   if isempty(avgWeightGradsSq_init)
      avgWeightGradsSq = zeros_ffNN_weightDimSizes;
      avgWeightGradsSq_startAtZero(1 : numTransforms) = true;
   else
      avgWeightGradsSq = avgWeightGradsSq_init;
      avgWeightGradsSq_startAtZero(1 : numTransforms) = false;
   endif   
   
   trainCostAvg_exclWeightPenalty_approx = ...
      validCostAvg_exclWeightPenalty = ...
      testCostAvg_exclWeightPenalty = 0;
   trainAccuracyAvg_text = validAccuracyAvg_text = '';
   trainCostsAvg_exclWeightPenalty_approx = ...
      validCostsAvg_exclWeightPenalty = [];
      
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

   valid_provided = ~(isempty(validInput) ...
      || isempty(validTargetOutput));   
   if (valid_provided)
      validBatchDim = max([batchDim ...
         arrNumDims(validInput) ...
         arrNumDims(validTargetOutput)]);
      validNumBatches = max...
         ([size(validInput, validBatchDim) ...
         size(validTargetOutput, validBatchDim)]);
   endif
   bestStop = valid_provided && bestStop;
   if (bestStop)
      ffNN_avgWeights_best = ffNN_avgWeights;
      validCostAvg_exclWeightPenalty_best = Inf;
      toSaveBest = false;
   endif 
   
   test_provided = ~(isempty(testInput) ...
      || isempty(testTargetOutput));
   if (test_provided)
      testBatchDim = max([batchDim ...
         arrNumDims(testInput) ...
         arrNumDims(testTargetOutput)]);
      testNumBatches = max...
         ([size(testInput, testBatchDim) ...
         size(testTargetOutput, testBatchDim)]);
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
      trainAccuracyAvg_currChunk = chunk = batch_inChunk = 0;
   
   saveFileName_upper = upper(saveFileName);
  
   overview(ffNN);
fprintf('\n\nTRAIN FORWARD-FEEDING NEURAL NETWORK (FFNN) (METHOD: RMSPROP):\n\n');
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
   trainRandShuff = trainRandShuff && (trainNumBatches > 1);   
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

   fprintf('      Weight Connectivity Probabilities, Penalty Methods & Penalty Terms:\n');
   weightRegulFuncs = weightRegulArgs_list{1};
   weightRegulParams = weightRegulArgs_list{2};
   for (l = 1 : numTransforms)      
      if (l > 1)
         if (length(connectProbs) < l)
            connectProbs(l) = connectProbs(l - 1);
         endif
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
            sprintf(', penalty term = %g', ...
            weightRegulParams(l));
      endif      
      fprintf('         Layer #%i: %i%%, %s%s\n', l, ...
         100 * connectProbs(l), weightRegulFuncs{l}, ...
         weightRegulParam_print);
   endfor
   
   if (bestStop)
fprintf('      Model Selection by Best Validation Performance\n');
   endif
   
   fprintf('      Saving Results in %s on Working Directory every %i Minutes\n', ...
      saveFileName_upper, saveEvery_numMins);
      
   fprintf('\n');
   
   fprintf('   TRAINING PROGRESS:\n');
% fprintf(cstrcat('      (pre-terminate by "', zzzBORED, '" key stroke)\n'));
fprintf('      Training Avg Cost (excl Weight Penalty) approx''d w/ each chunk of %i batches\n',
      trainCostApproxChunk_numBatches);
fprintf('      Validation Avg Cost (excl Weight Penalty) updated every %i batches\n', ...
      validCostCalcInterval_numChunks ...
      * trainCostApproxChunk_numBatches);
   if (costFuncType_isCrossEntropy)
fprintf('         (Classification Confidence %%s in brackets)\n');
else
fprintf('         (Root Mean Square Error (RMSE) in brackets)\n');
   endif
   
   if (plotLearningCurves)
      figure;
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
         
         ffNN_temp = ffNN;  
         if (momentumRate) && (nesterovAccGrad)
            for (l = 1 : numTransforms)                
               ffNN_temp.weights{l} += momentumRate ...
                  * immedWeightChangesMemory{l};
            endfor
         endif
         for (l = 1 : numTransforms)
            connectivitiesOnOff{l} = binornd(1, ...
               connectProbs(l), weightDimSizes{l});
         endfor
         [weightGrads, ~, ~, ~, ~, ~, weightRegulParams] = ...
            fProp_bProp(ffNN_temp, trainInput_batch, ...
            trainTargetOutput_batch, ...
         targetOutputs_areClassIndcsColVecs_ofNumClasses, ...
            {weightRegulFuncs weightRegulParams}, true, ...
            connectivitiesOnOff);
            
         for (l = 1 : numTransforms)
            if (avgWeightGradsSq_startAtZero(l))
               avgWeightGradsSq{l} = weightGrads{l} .^ 2;
               avgWeightGradsSq_startAtZero(l) = false;
            else
               avgWeightGradsSq{l} = decayRate ...
                  * avgWeightGradsSq{l} + (1 - decayRate) ...
                  * (weightGrads{l} .^ 2);
            endif
            ffNN.weights{l} += ...
               immedWeightChangesMemory{l} = - stepRate ...
               .* div0(weightGrads{l}, ...
               sqrt(avgWeightGradsSq{l}));
            % 0 * momentumRate ...
            % * ffNN_immedWeightChangesMemory_updated{l} ...   
            % Geoffrey Hinton: standard momentum does not
            % seem to help as much as expected -> need
            % additional investigation. Hence we are
            % multiplying the first term with 0 for now.
            
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
         
         ffNN_avgWeights = avgWeights_byConnectProbs...
            (ffNN, connectProbs); 
         [trainCostAvg_exclWeightPenalty_currBatch ...
            trainAccuracyAvg_currBatch] = ...
            costAvg_exclWeightPenalty(ffNN_avgWeights, ...
            trainInput_batch, trainTargetOutput_batch, ...
         targetOutputs_areClassIndcsColVecs_ofNumClasses, ...
            trainBatchDim);
         
         batch_inChunk++;
         trainCostAvg_exclWeightPenalty_currChunk += ...
            (trainCostAvg_exclWeightPenalty_currBatch ...
            - trainCostAvg_exclWeightPenalty_currChunk) ...
            / batch_inChunk;
         trainAccuracyAvg_currChunk += ...
            (trainAccuracyAvg_currBatch ...
            - trainAccuracyAvg_currChunk) ...
            / batch_inChunk;
         
         trainEnd = (batch == trainNumBatches) ...
            && (epoch == trainNumEpochs);
         
         if (batch_inChunk == ...
            trainCostApproxChunk_numBatches) || (trainEnd)
                        
            chunk++;
         trainCostsAvg_exclWeightPenalty_approx(chunk) = ...
               trainCostAvg_exclWeightPenalty_currChunk;
            
            if (costFuncType_isCrossEntropy)
               trainAccuracyAvg_text = sprintf...
                  (' (%.3g%%)', 100 * ...
                  trainAccuracyAvg_currChunk);
            else
               trainAccuracyAvg_text = sprintf...
                  (' (%.3g)', sqrt(2 * ...
                  trainCostAvg_exclWeightPenalty_currChunk));
            endif
         
            if (valid_provided && ...
               ((mod(chunk, ...
               validCostCalcInterval_numChunks) == 0) || ...
               trainEnd))
            
               [costAvg_valid validAccuracyAvg] = ...
                  costAvg_exclWeightPenalty...
                  (ffNN_avgWeights, validInput, ...
                  validTargetOutput, ...
         targetOutputs_areClassIndcsColVecs_ofNumClasses, ...
                  validBatchDim);
               validCostAvg_exclWeightPenalty = ...
                  validCostsAvg_exclWeightPenalty(chunk) = ...
                  costAvg_valid;
               if (costFuncType_isCrossEntropy)
                  validAccuracyAvg_text = sprintf...
                     (' (%.3g%%)', 100 * validAccuracyAvg);
               else
                  validAccuracyAvg_text = sprintf...
                     (' (%.3g)', sqrt(2 * ...
                     validCostAvg_exclWeightPenalty));
               endif
               
               if (bestStop && ...
                  (validCostAvg_exclWeightPenalty ...
                  < validCostAvg_exclWeightPenalty_best))
                  
                  ffNN_avgWeights_best = ffNN_avgWeights;
                  
                  if (trainNumBatches == 1)
                     trainCostAvg_exclWeightPenalty_best = ...
                     trainCostAvg_exclWeightPenalty_currBatch;
                     trainAccuracyAvg_best = ...
                        trainAccuracyAvg_currBatch;
                     if (costFuncType_isCrossEntropy)
                        trainAccuracyAvg_text_best = sprintf...
                           (' (%.3g%%)', 100 * ...
                           trainAccuracyAvg_best);
                     else
                        trainAccuracyAvg_text_best = sprintf...
                           (' (%.3g)', sqrt(2 * ...
                        trainCostAvg_exclWeightPenalty_best));
                     endif   
                  else
                     trainCostAvg_exclWeightPenalty_best = ...
                     trainCostAvg_exclWeightPenalty_currChunk;
                     trainAccuracyAvg_best = ...
                        trainAccuracyAvg_currChunk;
                     trainAccuracyAvg_text_best = ...
                        trainAccuracyAvg_text;                     
                  endif
                  
                  validCostAvg_exclWeightPenalty_best = ...
                     validCostAvg_exclWeightPenalty;
                  validAccuracyAvg_best = validAccuracyAvg;
                  validAccuracyAvg_text_best = ...
                     validAccuracyAvg_text;
                     
                  toSaveBest = true;
                  
               endif
            
            else
            
               validCostsAvg_exclWeightPenalty(chunk) = NA;            
            
            endif
            
            if (time > lastSaveTime + saveEvery_numMins * 60)
               if (bestStop)
                  if (toSaveBest)
                     saveFile(ffNN_avgWeights_best, ...
                        saveFileName);
                     lastSaveTime = time;                  
                     toSaveBest = false;
                  endif
               else
                  saveFile(ffNN, saveFileName);
                  lastSaveTime = time;
               endif
               
            endif            
            
            if (bestStop) && ...
               isfinite(validCostAvg_exclWeightPenalty_best)
               validReport_text = sprintf('%.3g Best %.3g%s', ...
                  validCostAvg_exclWeightPenalty, ...
                  validCostAvg_exclWeightPenalty_best, ...
                  validAccuracyAvg_text_best);
            else
               validReport_text = sprintf('%.3g%s', ...
                  validCostAvg_exclWeightPenalty, ...
                  validAccuracyAvg_text);
            endif            
            
            trainCurrTime = time;
            trainElapsedTime_numMins = ...
               (trainCurrTime - trainStartTime) / 60;
fprintf('\r      Epoch %i Batch %i: TRAIN %.3g%s, VALID %s, elapsed %.1fm   ', ...
               epoch, batch, ...
               trainCostAvg_exclWeightPenalty_currChunk, ...
               trainAccuracyAvg_text, validReport_text, ...
               trainElapsedTime_numMins);
            
            if (plotLearningCurves)               
               ffNN_plotLearningCurves...
                  (trainCostAvg_exclWeightPenalty_currChunk, ...
                  trainAccuracyAvg_text, ...
                  trainCostsAvg_exclWeightPenalty_approx, ...   
                  validReport_text, ...
                  validCostsAvg_exclWeightPenalty, ...  
                  chunk, trainCostApproxChunk_numBatches, ...
                  batchSize, trainElapsedTime_numMins);
            endif
               
            trainCostAvg_exclWeightPenalty_currChunk = ...
               trainAccuracyAvg_currChunk = batch_inChunk = 0;  
 
         endif
         
      endfor
   
   endfor

fprintf('\n\n   RESULTS:   Training Finished w/ Following Avg Costs (excl Weight Penalty):\n');
   
   if (bestStop)
      
      ffNN_avgWeights = ffNN_avgWeights_best;
      
      trainCostAvg_exclWeightPenalty_approx = ...
         trainCostAvg_exclWeightPenalty_best;
      trainAccuracyAvg = trainAccuracyAvg_best;
      trainAccuracyAvg_text = trainAccuracyAvg_text_best;      
         
      validCostAvg_exclWeightPenalty = ...
         validCostAvg_exclWeightPenalty_best;
      validAccuracyAvg = validAccuracyAvg_best;         
      validAccuracyAvg_text = validAccuracyAvg_text_best;
      
   else
      
      if (trainNumBatches == 1)
         trainCostAvg_exclWeightPenalty_approx = ...
            trainCostAvg_exclWeightPenalty_currBatch;
         if (costFuncType_isCrossEntropy)   
            trainAccuracyAvg_text = sprintf(' (%.3g%%)', ...
               100 * trainAccuracyAvg_currBatch);
         else
            trainAccuracyAvg_text = sprintf(' (%.3g)', ...
               sqrt(2 ...
               * trainCostAvg_exclWeightPenalty_currBatch));
         endif   
      else
         trainCostAvg_exclWeightPenalty_approx = ...
            trainCostsAvg_exclWeightPenalty_approx(end);
      endif
   
   endif
   
   if (trainNumBatches == 1)
      fprintf('      Training: %.3g%s', ...
         trainCostAvg_exclWeightPenalty_approx, ...
         trainAccuracyAvg_text);
   else
      fprintf('      Training (approx''d by last chunk): %.3g%s', ...
         trainCostAvg_exclWeightPenalty_approx, ...
         trainAccuracyAvg_text);
   endif
   
   if (trainNumBatches == 1) && ...
      (costFuncType_isCrossEntropy)      
      pred = predict(ffNN_avgWeights, trainInput_batch);
      switch (costFuncType)
         case ('CE-L')               
            acc = binClassifAccuracy(pred, ...
               trainTargetOutput_batch);
         case ('CE-S')
            acc = classifAccuracy(pred, ...
               trainTargetOutput_batch);
      endswitch
      fprintf(', Actual Classification Accuracy %.3g%%', ...
         100 * acc);      
   endif
   fprintf('\n');
   
   if (valid_provided)

      fprintf('      Validation: %.3g%s', ...
         validCostAvg_exclWeightPenalty, ...
         validAccuracyAvg_text);
      
      if (validNumBatches == 1) && ...
         (costFuncType_isCrossEntropy)         
         pred = predict(ffNN_avgWeights, validInput);
         switch (costFuncType)         
            case ('CE-L')               
               acc = binClassifAccuracy(pred, ...
                  validTargetOutput);
            case ('CE-S')
               acc = classifAccuracy(pred, ...
                  validTargetOutput);
         endswitch
         fprintf(', Actual Classification Accuracy %.3g%%', ...
            100 * acc);         
      endif
      
      fprintf('\n');
         
   endif
   
   if (test_provided)
   
      [testCostAvg_exclWeightPenalty testAccuracyAvg] = ...
         costAvg_exclWeightPenalty(ffNN_avgWeights, ...
         testInput, testTargetOutput, ...
         targetOutputs_areClassIndcsColVecs_ofNumClasses, ...
         testBatchDim);
         
      if (costFuncType_isCrossEntropy)
         testAccuracyAvg_text = sprintf...
            (' (%.3g%%)', 100 * testAccuracyAvg);         
      else
         testAccuracyAvg_text = '';
      endif
      
      fprintf('      Test: %.3g%s', ...
         testCostAvg_exclWeightPenalty, ...
         testAccuracyAvg_text);
         
      if (costFuncType_isCrossEntropy) && ...
         (testNumBatches == 1)
         pred = predict(ffNN_avgWeights, testInput);
         switch (costFuncType)         
            case ('CE-L')               
               acc = binClassifAccuracy(pred, ...
                  testTargetOutput);
            case ('CE-S')
               acc = classifAccuracy(pred, testTargetOutput);
         endswitch
         fprintf(', Actual Classification Accuracy %.3g%%', ...
            100 * acc);
      endif      
      
      fprintf('\n');
      
   endif  

   fprintf('\n');
   
   saveFile(ffNN_avgWeights, saveFileName);
   
endfunction