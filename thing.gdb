break /nix/store/73b33yxdvy3fpv2x0l1l17sqa58amsxx-odin-dev-2026-05/share/core/strings/builder.odin:170
commands
silent
set $ignore = 0
set $frame = $_caller
while $frame != 0
  if $_caller_is("log.info", $ignore)
    set $ignore = 1
  end
  set $ignore = $ignore + 1
  set $frame = $_caller($ignore)
end
if $ignore == 0
  # no log.info found → stop
else
  continue
end
end
