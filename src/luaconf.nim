


when defined(windows):
    import private/confwindows
    export confwindows
else:
    import private/confposix
    export confposix

const LUA_ENV* = "_ENV"
