import std/[logging, terminal]

type
  ColorConsoleLogger* = ref object of ConsoleLogger

# Override the base log method
method log*(logger: ColorConsoleLogger, level: Level, args: varargs[string, `$`]) =
  if level >= logger.levelThreshold:
    # Determine which stream we are writing to
    let outStream = if logger.useStderr: stderr else: stdout

    # 1. Set the color based on the log level
    case level
    of lvlDebug: setForegroundColor(outStream, fgBlue)
    of lvlInfo: setForegroundColor(outStream, fgWhite)
    of lvlNotice: setForegroundColor(outStream, fgGreen)
    of lvlWarn: setForegroundColor(outStream, fgYellow)
    of lvlError, lvlFatal: setForegroundColor(outStream, fgRed)
    else: discard

    # 2. Delegate the actual formatting and printing to the base ConsoleLogger
    procCall ConsoleLogger(logger).log(level, args)

    # 3. Immediately reset the terminal back to normal
    resetAttributes(outStream)

# Constructor for your new logger
proc newColorLogger*(levelThreshold = lvlAll, fmtStr = defaultFmtStr,
    useStderr = false): ColorConsoleLogger =
  new result
  result.fmtStr = fmtStr
  result.levelThreshold = levelThreshold
  result.useStderr = useStderr

proc initLogging*(consoleLvl: Level) =
  let logFormat = "[$levelname] $datetime: "

  # Use the new Color Logger for the terminal
  let consoleLog = newColorLogger(levelThreshold = consoleLvl,
      fmtStr = logFormat)

  # Keep the standard File Logger for plain-text logs
  let fileLog = newFileLogger("luavm.log", levelThreshold = lvlAll,
      fmtStr = logFormat)

  addHandler(consoleLog)
  addHandler(fileLog)
