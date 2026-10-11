# Executed in the connected badge's REPL before filesystem deployment.
import supervisor
import os
supervisor.runtime.autoreload = False
print("AUTORELOAD_DISABLED")
print("BOARD:", os.uname())
