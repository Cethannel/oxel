import gdb

class IgnoreLogBreakpoint(gdb.Breakpoint):
    def __init__(self, spec):
        spec = "/nix/store/73b33yxdvy3fpv2x0l1l17sqa58amsxx-odin-dev-2026-05/share/core/strings/builder.odin:170"
        super().__init__(spec, gdb.BP_BREAKPOINT, internal=False)
        self.silent = True

    def stop(self):
        frame = gdb.selected_frame()
        while frame:
            func = frame.name()
            if func:
                # Add or remove logging functions here
                log_functions = {
                    "log::info",
                    "log::debug",
                    "log::warn",
                    "log::error",
                    "log::fatal",
                    "log::trace",
                    "log::print",      # if you have this
                    "engine::vk_assert",      # if you have this
                    # Add more as needed
                }
                
                #print("Frame: " + func + "\n")
                # Check for exact match or substring (adjust as you prefer)
                for lf in log_functions:
                    if lf in func or func in lf:   # flexible matching
                        return False               # Continue execution (ignore bp)
            
            frame = frame.older()
        
        return True  # Stop in GDB
