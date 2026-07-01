/**
 * Will wait for an iframe to be ready
 * for DOM manipulation. Just listening for
 * the load event will only work if the iframe
 * is not already loaded. If so, it is necessary
 * to observe the readyState. The issue here is
 * that Chrome will initialize iframes with
 * "about:blank" and set its readyState to complete.
 * So it is furthermore necessary to check if it's
 * the readyState of the target document property.
 * Errors that may occur when trying to access the iframe
 * (Same-Origin-Policy) will be catched and the error
 * function will be called.
 * @param {jquery} $i - The jQuery iframe element
 * @param {function} successFn - The callback on success. Will
 * receive the jQuery contents of the iframe as a parameter
 * @param {function} errorFn - The callback on error
 */
var onIframeReady = function($i, successFn, errorFn) {
    try {
        const iCon = $i.first()[0].contentWindow,
            bl = "about:blank",
            compl = "complete";
        const callCallback = () => {
            try {
                const $con = $i.contents();
                if($con.length === 0) { // https://git.io/vV8yU
                    throw new Error("iframe inaccessible");
                }
                successFn($con);
            } catch(e) { // accessing contents failed
                errorFn();
            }
        };
        const observeOnload = () => {
            $i.on("load.jqueryMark", () => {
                try {
                    const src = $i.attr("src").trim(),
                        href = iCon.location.href;
                    if(href !== bl || src === bl || src === "") {
                        $i.off("load.jqueryMark");
                        callCallback();
                    }
                } catch(e) {
                    errorFn();
                }
            });
        };
        if(iCon.document.readyState === compl) {
            const src = $i.attr("src").trim(),
                href = iCon.location.href;
            if(href === bl && src !== bl && src !== "") {
                observeOnload();
            } else {
                callCallback();
            }
        } else {
            observeOnload();
        }
    } catch(e) { // accessing contentWindow failed
        errorFn();
    }
};
