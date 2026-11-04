// Rig probe for fx/Glitch.qml: the production component with its test hooks set from
// the environment. RIG_GLITCH_STEP_MS stretches each step for screenshots (default 42),
// RIG_GLITCH_SEED fixes the random values (default: random). Every step is logged.
import QtQuick
import Quickshell
import qs.fx

ShellRoot {
    Glitch {
        stepMs: parseInt(Quickshell.env("RIG_GLITCH_STEP_MS") ?? "42") || 42
        fixedSeed: parseFloat(Quickshell.env("RIG_GLITCH_SEED") ?? "-1")
        logSteps: true
    }
}
