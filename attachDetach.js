// attachDetach.js
(function() {
    let pid = get_pid();
    log(`[AttachDetach] Targeting PID: ${pid}`);

    let attachResp = send_command(`vAttach;${pid.toString(16)}`);
    log(`[AttachDetach] Attach response: ${attachResp}`);

    if (attachResp && attachResp.startsWith('T')) {
        log("[AttachDetach] Successfully attached. Triggering continue...");
        let contResp = send_command("c");
        log(`[AttachDetach] Continue response: ${contResp}`);
    } else {
        log("[AttachDetach] Failed to attach or unexpected response.");
    }

    // Detach sequence
    log("[AttachDetach] Detaching...");
    let detachResp = send_command("D");
    log(`[AttachDetach] Detach response: ${detachResp}`);
})();
