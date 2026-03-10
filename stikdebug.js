// STIK Debug Script for JIT Activation
(function() {
    console.log("STIK: Initializing JIT activation sequence...");
    if (typeof JIT !== 'undefined') {
        JIT.enable();
        console.log("STIK: JIT enabled successfully.");
    } else {
        console.log("STIK: JIT interface not found, assuming native activation.");
    }
})();
