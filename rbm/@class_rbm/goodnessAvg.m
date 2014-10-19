function m = goodnessAvg(rbm, hid_rowMat, vis_rowMat)

   m = trace...
      ((addBiasElems(hid_rowMat, rbm.addBiasHid) ...
      * rbm.weights) ...
      * addBiasElems(vis_rowMat, rbm.addBiasVis)')...
      / rows(hid_rowMat);

endfunction