/* CRON.rexx  -  cron for Regina REXX (Linux, Windows)
 *
 * One external function, CRON(action, arg1, arg2, arg3), plus a command line.
 * Pure REXX; the only OS calls are ADDRESS SYSTEM (sleep, start a job), and
 * those are switched on the OS name from PARSE SOURCE.
 *
 * FUNCTION USE (file must be named CRON.rexx - upper-case "CRON" - and its folder must be on PATH or in REGINA_MACROS; Regina on Linux matches the case of the called name):
 *   CRON('VALID', expr)                  -> 1 / 0
 *   CRON('MATCH', expr [, stamp])        -> 1 / 0   does expr fire at stamp?
 *   CRON('NEXT',  expr [, stamp])        -> 'YYYY-MM-DD HH:MM' of next fire
 *                                           strictly after stamp ('' if none
 *                                           within ~8 years)
 *   CRON('TICK',  crontab [, stamp [, opts]])
 *                                        -> run every crontab job due at
 *                                           stamp; returns number started
 *   CRON('RUN',   crontab [, opts])      -> scheduler loop (never returns
 *                                           unless opts has ONCE)
 *   CRON('ADD',    crontab, expr, command) -> append a job (expr validated;
 *                                           file created if missing)
 *   CRON('LIST',   crontab)              -> numbered jobs with next fire time
 *   CRON('REMOVE', crontab, n)           -> delete job number n (as in LIST)
 *   CRON('STOP',   crontab)              -> ask a running RUN on that crontab
 *                                           to exit (within ~5 s); it works by
 *                                           creating the file <crontab>.stop
 *   CRON('STATUS', crontab)              -> 'running since ...' or 'not running'
 *                                           (RUN writes a heartbeat file
 *                                           <crontab>.status every few seconds)
 *   CRON('SLEEP', seconds)               -> portable sleep
 *   CRON('OS')                           -> 'UNIX' or 'WIN'
 *   stamp = 'YYYY-MM-DD HH:MM' (also 'YYYY-MM-DDTHH:MM[:SS]'); default = now.
 *   Failures return a string starting 'ERROR:'.
 *   opts (words): SYNC    run jobs one after another, wait for each
 *                 VERBOSE print a line per job started
 *                 DRYRUN  print the command line instead of running it
 *                 ONCE    RUN: do the current minute only, then return
 *
 * COMMAND LINE:
 *   regina CRON.rexx run   crontab [opts]
 *   regina CRON.rexx tick  crontab [stamp]       (for testing / OS scheduler)
 *   regina CRON.rexx next  "m h dom mon dow" [stamp]
 *   regina CRON.rexx match "m h dom mon dow" [stamp]
 *   regina CRON.rexx valid "m h dom mon dow"
 *   regina CRON.rexx add    crontab "m h dom mon dow" command...
 *   regina CRON.rexx list   crontab
 *   regina CRON.rexx remove crontab n
 *   regina CRON.rexx stop   crontab              (stops the running 'run')
 *   regina CRON.rexx status crontab
 *
 * EXPRESSIONS: 5 fields  minute hour day-of-month month day-of-week
 *   *  a  a-b  a,b,c  star/n  a-b/n  a/n ; month JAN..DEC ; weekday SUN..SAT
 *   (0 and 7 = Sunday) ; @yearly @annually @monthly @weekly @daily
 *   @midnight @hourly.  Like Vixie cron: if day-of-month and day-of-week are
 *   both restricted, a day matching EITHER fires.
 *
 * CRONTAB FILE: standard lines  "expr command"; '#' comments and blank lines
 *   skipped; NAME=value lines set an environment variable for the jobs. The
 *   file is re-read every minute, so edits take effect without a restart.
 *   Jobs are started in the background by default (SYNC to wait).
 *
 * REXX JOBS: a job whose command starts with a .rex / .rexx file is run as
 *   "regina <command>" (set environment variable CRON_REXX to use another
 *   interpreter or a full path). This avoids the Windows file-association
 *   launcher and its "Press ENTER key to exit.." prompt.
 *
 * TESTING: environment variable CRON_OS=WIN or UNIX overrides the OS check.
 */

parse source srcos calltype .

if calltype == 'COMMAND' then do
  parse arg action restline
  action = translate(action)
  select
    when action == 'RUN' then do
      parse var restline file opts
      res = Run(file, opts)
    end
    when action == 'TICK' then do
      parse var restline file stamp
      res = Tick(file, stamp, '')
    end
    when action == 'NEXT' | action == 'MATCH' | action == 'VALID' then do
      if left(restline,1) == '@' then parse var restline expr stamp
      else do
        parse var restline f1 f2 f3 f4 f5 stamp
        expr = f1 f2 f3 f4 f5
      end
      if action == 'NEXT'  then res = DoNext(expr, stamp)
      if action == 'MATCH' then res = DoMatch(expr, stamp)
      if action == 'VALID' then do
        c = Compile(expr)
        if left(c,3) == 'ERR' then res = 'ERROR:' substr(c,4)
        else res = 1
      end
    end
    when action == 'STATUS' then do
      parse var restline file .
      res = DoStatus(file)
    end
    when action == 'STOP' then do
      parse var restline file .
      res = DoStop(file)
    end
    when action == 'LIST' then do
      parse var restline file .
      res = DoList(file)
    end
    when action == 'REMOVE' then do
      parse var restline file n .
      res = DoRemove(file, n)
    end
    when action == 'ADD' then do
      parse var restline file restline
      if left(file,1) == '@' | left(file,1) == '*' | datatype(left(file,1),'W') then do
        say 'ERROR: the crontab file comes first:  add <crontab> <expr> <command>'
        exit 1
      end
      if left(restline,1) == '@' then parse var restline expr cmd
      else do
        parse var restline f1 f2 f3 f4 f5 cmd
        expr = f1 f2 f3 f4 f5
      end
      res = DoAdd(file, expr, cmd)
    end
    otherwise do
      say 'usage: regina CRON.rexx run|tick|next|match|valid|add|list|remove|stop|status ...  (see header)'
      exit 2
    end
  end
  if res \== '' then say res
  if left(res,6) == 'ERROR:' then exit 1
  exit 0
end

/* ---- function entry ---- */
parse arg action, a1, a2, a3
action = translate(strip(action))
select
  when action == 'VALID' then do
    c = Compile(a1)
    return (left(c,3) \== 'ERR')
  end
  when action == 'MATCH' then return DoMatch(a1, a2)
  when action == 'NEXT'  then return DoNext(a1, a2)
  when action == 'TICK'  then return Tick(a1, a2, a3)
  when action == 'RUN'   then return Run(a1, a2)
  when action == 'ADD'    then return DoAdd(a1, a2, a3)
  when action == 'LIST'   then return DoList(a1)
  when action == 'STOP'   then return DoStop(a1)
  when action == 'STATUS' then return DoStatus(a1)
  when action == 'REMOVE' then return DoRemove(a1, a2)
  when action == 'SLEEP' then do
    call CronSleep a1
    return ''
  end
  when action == 'OS' then do
    if IsWin() then return 'WIN'
    return 'UNIX'
  end
  otherwise return 'ERROR: unknown action' action
end

/* ------------------------------------------------------------------ */
/* platform helpers                                                    */
/* ------------------------------------------------------------------ */

IsWin: procedure
  os = value('CRON_OS',,'ENVIRONMENT')
  if os == '' then parse source os .
  return (left(translate(os),3) == 'WIN')

CronSleep: procedure
  parse arg n
  if \datatype(n,'W') then n = 1
  if n < 1 then n = 1
  if IsWin() then address system 'ping -n' n+1 '127.0.0.1 >nul 2>&1'
  else address system 'sleep' n
  return

/* start one job; returns rc (0 when started in background / dry run) */
RunJob: procedure
  parse arg cmd, opts
  opts = translate(opts)
  /* A command starting with a REXX program (x.rex / x.rexx) is run through the
     interpreter. Started via the Windows file association it would wait for
     "Press ENTER key to exit..". Interpreter = env CRON_REXX, default 'regina'. */
  w1 = translate(strip(word(cmd,1),'B','"'))
  if right(w1,4) == '.REX' | right(w1,5) == '.REXX' then do
    interp = value('CRON_REXX',,'ENVIRONMENT')
    if interp == '' then interp = 'regina'
    cmd = interp cmd
  end
  sync = (wordpos('SYNC', opts) > 0)
  if sync then full = cmd
  else if IsWin() then full = 'start "cron" /b cmd /c' cmd
  else full = '(' cmd ') &'
  if wordpos('DRYRUN', opts) > 0 then do
    say 'DRYRUN:' full
    return 0
  end
  address system full
  return rc

/* ------------------------------------------------------------------ */
/* crontab editing: ADD / LIST / REMOVE                                */
/* ------------------------------------------------------------------ */

Norm: procedure
  parse arg line
  return strip(translate(line, '  ', d2c(9)d2c(13)))

/* 1 if the (normalised) line is a job, 0 for blank / comment / NAME=value */
JobLine: procedure
  parse arg line
  if line == '' | left(line,1) == '#' then return 0
  w1 = word(line,1)
  if left(w1,1) \== '@' & pos('=', w1) > 0 then return 0
  return 1

SplitJob: procedure
  parse arg line
  if left(line,1) == '@' then return word(line,1)'|'subword(line,2)
  return subword(line,1,5)'|'subword(line,6)

CountJobs: procedure
  parse arg file
  n = 0
  if stream(file,'C','QUERY EXISTS') == '' then return 0
  do while lines(file) > 0
    if JobLine(Norm(linein(file))) then n = n + 1
  end
  call stream file, 'C', 'CLOSE'
  return n

DelFile: procedure
  parse arg f
  if IsWin() then address system 'del /q "'f'" >nul 2>&1'
  else address system 'rm -f "'f'"'
  return

/* 'YYYY-MM-DD HH:MM:SS' now (truncated seconds) */
Now: procedure
  do until dt == date('S')
    dt = date('S')
    tm = left(time('L'),8)
  end
  return left(dt,4)'-'substr(dt,5,2)'-'substr(dt,7,2) tm

/* seconds since 0001-01-01, truncated clock - used for heartbeat age */
AbsSecs: procedure
  numeric digits 15
  do until dt == date('S')
    dt = date('S')
    tm = left(time('L'),8)
  end
  parse var tm h ':' mi ':' sec
  return date('B') * 86400 + h*3600 + mi*60 + sec

Heartbeat: procedure
  parse arg statf, started, lasttick, total
  call stream statf, 'C', 'OPEN WRITE REPLACE'
  call lineout statf, started
  call lineout statf, AbsSecs()
  call lineout statf, lasttick
  call lineout statf, total
  call stream statf, 'C', 'CLOSE'
  return

DoStatus: procedure
  parse arg file
  numeric digits 15
  if stream(file,'C','QUERY EXISTS') == '' then return 'ERROR: crontab not found:' file
  statf = file'.status'
  if stream(statf,'C','QUERY EXISTS') == '' then return 'not running'
  started = linein(statf)
  beat = linein(statf)
  lasttick = linein(statf)
  total = linein(statf)
  call stream statf, 'C', 'CLOSE'
  if \datatype(beat,'W') then return 'not running'
  age = AbsSecs() - beat
  if age > 15 then return 'not running (last seen' age 'seconds ago; was started' started')'
  return 'running since' started', last minute checked' lasttick', jobs started:' total

DoStop: procedure
  parse arg file
  if stream(file,'C','QUERY EXISTS') == '' then return 'ERROR: crontab not found:' file
  call lineout file'.stop', 'stop'
  call stream file'.stop', 'C', 'CLOSE'
  return 'OK: stop requested (takes up to 5 seconds)'

DoAdd: procedure
  parse arg file, expr, cmd
  expr = space(expr, 1)
  cmd = strip(cmd)
  c = Compile(expr)
  if left(c,3) == 'ERR' then return 'ERROR:' substr(c,4)
  if cmd == '' then return 'ERROR: empty command'
  n = CountJobs(file)
  if stream(file,'C','QUERY EXISTS') \== '' then do
    sz = chars(file)
    if sz > 0 then do
      last = charin(file, sz, 1)
      call stream file, 'C', 'CLOSE'
      if last \== d2c(10) then call lineout file, ''     /* end the last line */
    end
    call stream file, 'C', 'CLOSE'
  end
  call lineout file, expr cmd
  call stream file, 'C', 'CLOSE'
  return 'OK: added job' n + 1

DoList: procedure
  parse arg file
  if stream(file,'C','QUERY EXISTS') == '' then return 'ERROR: crontab not found:' file
  out = ''
  n = 0
  do while lines(file) > 0
    line = Norm(linein(file))
    if \JobLine(line) then iterate
    n = n + 1
    parse value SplitJob(line) with expr '|' cmd
    c = Compile(expr)
    if left(c,3) == 'ERR' then info = 'INVALID'
    else info = DoNext(expr, '')
    if n > 1 then out = out || x2c('0A')
    out = out || right(n,3)'  'left(expr,15)'  'left(info,16)'  'cmd
  end
  call stream file, 'C', 'CLOSE'
  if n == 0 then return '(no jobs)'
  return out

DoRemove: procedure
  parse arg file, k
  if stream(file,'C','QUERY EXISTS') == '' then return 'ERROR: crontab not found:' file
  if \datatype(k,'W') then return 'ERROR: job number needed'
  if k < 1 then return 'ERROR: job number needed'
  tmp = file'.tmp'
  call DelFile tmp
  n = 0
  removed = ''
  do while lines(file) > 0
    raw = strip(linein(file), 'T', d2c(13))
    if JobLine(Norm(raw)) then do
      n = n + 1
      if n == k then do
        removed = Norm(raw)
        iterate
      end
    end
    call lineout tmp, raw
  end
  call stream file, 'C', 'CLOSE'
  call stream tmp, 'C', 'CLOSE'
  if removed == '' then do
    call DelFile tmp
    return 'ERROR: no job number' k
  end
  if stream(tmp,'C','QUERY EXISTS') == '' then do                       /* file had only that job */
    call DelFile file
    call stream file, 'C', 'OPEN WRITE REPLACE'
    call stream file, 'C', 'CLOSE'
  end
  else if IsWin() then address system 'move /y "'tmp'" "'file'" >nul'
  else address system 'mv -f "'tmp'" "'file'"'
  return 'OK: removed job' k':' removed

/* ------------------------------------------------------------------ */
/* scheduler                                                           */
/* ------------------------------------------------------------------ */

Run: procedure
  parse arg file, opts
  opts = translate(opts)
  if stream(file,'C','QUERY EXISTS') == '' then return 'ERROR: crontab not found:' file
  last = ''
  stopf = file'.stop'
  statf = file'.status'
  call DelFile stopf                      /* ignore a stale stop request */
  started = Now()
  lasttick = '-'
  total = 0
  if wordpos('ONCE', opts) == 0 then do   /* like cron: skip the minute already in progress */
    parse value ParseStamp('') with y m d h mi
    last = y m d h mi
  end
  do forever
    call Heartbeat statf, started, lasttick, total
    if stream(stopf,'C','QUERY EXISTS') \== '' then do
      call DelFile stopf
      call DelFile statf
      return 'OK: stopped'
    end
    st = ParseStamp('')
    parse var st y m d h mi
    key = y m d h mi
    if key \== last then do
      last = key
      n = Tick(file, y'-'m'-'d h':'mi, opts)
      lasttick = Now()
      if datatype(n,'W') then total = total + n
      if wordpos('ONCE', opts) > 0 then do
        call DelFile statf
        return n
      end
    end
    s = substr(time('L'),7,2) + 0
    call CronSleep min(60 - s, 5)           /* short naps so STOP is noticed */
  end

Tick: procedure
  parse arg file, stamp, opts
  opts = translate(opts)
  st = ParseStamp(stamp)
  if left(st,3) == 'ERR' then return 'ERROR:' substr(st,4)
  parse var st y m d h mi
  if stream(file,'C','QUERY EXISTS') == '' then return 'ERROR: crontab not found:' file
  shown = y'-'right(m,2,'0')'-'right(d,2,'0') right(h,2,'0')':'right(mi,2,'0')
  n = 0
  do while lines(file) > 0
    line = linein(file)
    line = strip(translate(line, '  ', d2c(9)d2c(13)))
    if line == '' | left(line,1) == '#' then iterate
    w1 = word(line,1)
    if left(w1,1) \== '@' & pos('=', w1) > 0 then do      /* NAME=value */
      parse var line name '=' val
      call value strip(name), strip(strip(val),'B','"'), 'ENVIRONMENT'
      iterate
    end
    if left(w1,1) == '@' then do
      expr = w1
      cmd = subword(line, 2)
    end
    else do
      expr = subword(line, 1, 5)
      cmd = subword(line, 6)
    end
    c = Compile(expr)
    if left(c,3) == 'ERR' then do
      say 'cron: skipped bad line "'line'":' substr(c,4)
      iterate
    end
    if cmd == '' then iterate
    if MatchC(c, y, m, d, h, mi) then do
      if wordpos('VERBOSE', opts) > 0 then say shown 'run:' cmd
      call RunJob cmd, opts
      n = n + 1
    end
  end
  call stream file, 'C', 'CLOSE'
  return n

/* ------------------------------------------------------------------ */
/* expression engine                                                   */
/* ------------------------------------------------------------------ */

DoMatch: procedure
  parse arg expr, ts
  c = Compile(expr)
  if left(c,3) == 'ERR' then return 'ERROR:' substr(c,4)
  st = ParseStamp(ts)
  if left(st,3) == 'ERR' then return 'ERROR:' substr(st,4)
  parse var st y m d h mi
  return MatchC(c, y, m, d, h, mi)

DoNext: procedure
  parse arg expr, ts
  c = Compile(expr)
  if left(c,3) == 'ERR' then return 'ERROR:' substr(c,4)
  st = ParseStamp(ts)
  if left(st,3) == 'ERR' then return 'ERROR:' substr(st,4)
  parse var st y m d h mi
  return NextC(c, y, m, d, h, mi)

/* compiled form:  mins|hrs|doms|mons|dows|domStar|dowStar  (sets as ' 1 5 ') */
Compile: procedure
  parse arg expr
  expr = strip(expr)
  if left(expr,1) == '@' then do
    select
      when translate(expr) == '@YEARLY' | translate(expr) == '@ANNUALLY' then expr = '0 0 1 1 *'
      when translate(expr) == '@MONTHLY'  then expr = '0 0 1 * *'
      when translate(expr) == '@WEEKLY'   then expr = '0 0 * * 0'
      when translate(expr) == '@DAILY' | translate(expr) == '@MIDNIGHT' then expr = '0 0 * * *'
      when translate(expr) == '@HOURLY'   then expr = '0 * * * *'
      otherwise return 'ERR unknown macro' expr
    end
  end
  if words(expr) \== 5 then return 'ERR need 5 fields, got' words(expr)
  parse var expr f1 f2 f3 f4 f5
  mins = ParseField(f1, 0, 59, 59, '', 0)
  if left(mins,3) == 'ERR' then return 'ERR minute:' substr(mins,4)
  hrs  = ParseField(f2, 0, 23, 23, '', 0)
  if left(hrs,3) == 'ERR' then return 'ERR hour:' substr(hrs,4)
  doms = ParseField(f3, 1, 31, 31, '', 0)
  if left(doms,3) == 'ERR' then return 'ERR day-of-month:' substr(doms,4)
  mons = ParseField(f4, 1, 12, 12, 'JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC', 1)
  if left(mons,3) == 'ERR' then return 'ERR month:' substr(mons,4)
  dows = ParseField(f5, 0, 7, 6, 'SUN MON TUE WED THU FRI SAT', 0)
  if left(dows,3) == 'ERR' then return 'ERR day-of-week:' substr(dows,4)
  ds = (left(f3,1) == '*')
  ws = (left(f5,1) == '*')
  return mins'|'hrs'|'doms'|'mons'|'dows'|'ds'|'ws

/* one field -> ' v1 v2 ... ' or 'ERR text' */
ParseField: procedure
  parse arg spec, lo, hi, starhi, names, nbase
  spec = translate(strip(spec))
  if spec == '' then return 'ERR empty field'
  set = ' '
  do while spec \== ''
    parse var spec part ',' spec
    if part == '' then return 'ERR empty list item'
    if pos('/', part) > 0 then do
      parse var part range '/' step
      if \datatype(step,'W') then return 'ERR bad step "'step'"'
      if step < 1 then return 'ERR bad step "'step'"'
    end
    else do
      range = part
      step = 1
    end
    if range == '*' then do
      a = lo
      b = starhi
    end
    else do
      if pos('-', range) > 0 then do
        parse var range a '-' b
        a = Atom(a, lo, hi, names, nbase)
        b = Atom(b, lo, hi, names, nbase)
      end
      else do
        a = Atom(range, lo, hi, names, nbase)
        if pos('/', part) > 0 then b = hi
        else b = a
      end
      if a == '' | b == '' then return 'ERR bad value in "'part'"'
      if a > b then return 'ERR reversed range "'part'"'
    end
    do v = a to b by step
      if hi == 7 & v == 7 then v2 = 0
      else v2 = v
      if pos(' 'v2' ', set) == 0 then set = set || v2 || ' '
    end
  end
  return set

/* number or 3-letter name -> number; '' when invalid/out of range */
Atom: procedure
  parse arg t, lo, hi, names, nbase
  if datatype(t,'W') then v = t + 0
  else do
    if names == '' | length(t) \== 3 then return ''
    p = wordpos(t, names)
    if p == 0 then return ''
    v = p - 1 + nbase
  end
  if v < lo | v > hi then return ''
  return v

MatchC: procedure
  parse arg c, y, m, d, h, mi
  parse var c mins '|' hrs '|' doms '|' mons '|' dows '|' ds '|' ws
  if pos(' 'mi+0' ', mins) == 0 then return 0
  if pos(' 'h+0' ', hrs) == 0 then return 0
  if pos(' 'm+0' ', mons) == 0 then return 0
  wd = (date('B', Ymd(y,m,d), 'S') + 1) // 7          /* 0 = Sunday */
  domok = (pos(' 'd+0' ', doms) > 0)
  dowok = (pos(' 'wd' ', dows) > 0)
  if ds | ws then return (domok & dowok)
  return (domok | dowok)

NextC: procedure
  parse arg c, y, m, d, h, mi
  parse var c mins '|' hrs '|' doms '|' mons '|' dows '|' ds '|' ws
  b0 = date('B', Ymd(y,m,d), 'S')
  t0 = h*60 + mi + 1                                  /* strictly after */
  if t0 >= 1440 then do
    b0 = b0 + 1
    t0 = 0
  end
  do b = b0 to b0 + 3000
    parse value date('S', b, 'B') with 1 yy 5 mm 7 dd
    mm = mm + 0
    dd = dd + 0
    if pos(' 'mm' ', mons) == 0 then iterate
    wd = (b + 1) // 7
    domok = (pos(' 'dd' ', doms) > 0)
    dowok = (pos(' 'wd' ', dows) > 0)
    if ds | ws then ok = (domok & dowok)
    else ok = (domok | dowok)
    if \ok then iterate
    if b == b0 then s0 = t0
    else s0 = 0
    do hh = s0 % 60 to 23
      if pos(' 'hh' ', hrs) == 0 then iterate
      if hh == s0 % 60 then m0 = s0 // 60
      else m0 = 0
      do nm = m0 to 59
        if pos(' 'nm' ', mins) > 0 then,
          return yy'-'right(mm,2,'0')'-'right(dd,2,'0') right(hh,2,'0')':'right(nm,2,'0')
      end
    end
  end
  return ''

/* ------------------------------------------------------------------ */
/* date helpers                                                        */
/* ------------------------------------------------------------------ */

Ymd: procedure
  parse arg y, m, d
  return right(y+0,4,'0')right(m+0,2,'0')right(d+0,2,'0')

DaysIn: procedure
  parse arg y, m
  if m == 2 then do
    if (y // 4 == 0 & y // 100 \== 0) | y // 400 == 0 then return 29
    return 28
  end
  if wordpos(m, '4 6 9 11') > 0 then return 30
  return 31

/* '' -> now; else 'YYYY-MM-DD HH:MM[:SS]' / '...THH:MM'.  Returns 'y m d h mi'
   (plain numbers) or 'ERR text'. */
ParseStamp: procedure
  parse arg ts
  ts = strip(ts)
  if ts == '' then do
    /* time('N') ROUNDS to the nearest second in Regina; time('L') and
       truncating is the true clock second. Re-read if midnight passed. */
    do until dt == date('S')
      dt = date('S')
      tm = left(time('L'),8)
    end
    parse var dt y 5 m 7 d
    parse var tm h ':' mi ':' .
  end
  else do
    ts = translate(ts, '   ', 'T-:')
    parse var ts y m d h mi .
    if h == '' then h = 0
    if mi == '' then mi = 0
  end
  if \datatype(y,'W') | \datatype(m,'W') | \datatype(d,'W') | \datatype(h,'W') | \datatype(mi,'W') then,
    return 'ERR bad timestamp (use YYYY-MM-DD HH:MM)'
  y = y+0; m = m+0; d = d+0; h = h+0; mi = mi+0
  if y < 1 | y > 9999 | m < 1 | m > 12 then return 'ERR bad timestamp date'
  if d < 1 | d > DaysIn(y,m) then return 'ERR bad timestamp date'
  if h < 0 | h > 23 | mi < 0 | mi > 59 then return 'ERR bad timestamp time'
  return y m d h mi
