-- Test bind for the rig: SUPER+F12 (sent with tests/rig/keys.sh) touches a marker
-- file so a test can prove the virtual keyboard reaches Hyprland's bind handling.
-- RICE_TESTBIN is exported by tests/rig/nested-hypr.sh into the compositor's env.
hl.bind("SUPER + F12", hl.dsp.exec_cmd('touch "$RICE_TESTBIN/bind-fired"'), { description = "rig test bind" })
