-- luacheck: ignore ly self warn info log luatexbase internalversion font fonts tex kpse status
local err, warn, info, log = luatexbase.provides_module({
    name               = "lyluatex",
    version            = '0',
    greinternalversion = internalversion,
    date               = "2018/02/02",
    description        = "Module lyluatex.",
    author             = "The Gregorio Project  − Jacques Peron <cataclop@hotmail.com>",
    copyright          = "2008-2018 - The Gregorio Project",
    license            = "MIT",
})

local md5 = require 'md5'
local lfs = require 'lfs'

ly = {}

local FILELIST
local OPTIONS = {}
local TEX_UNITS = {'bp', 'cc', 'cm', 'dd', 'in', 'mm', 'pc', 'pt', 'sp'}


--[[ ========================== Helper functions ========================== ]]

local function contains (table_var, value)
    for _, v in pairs(table_var) do
        if v == value then return true
        elseif v == 'false' and value == false then return true
        end
    end
end


local function convert_unit(value)
    return tonumber(value) or tex.sp(value) / tex.sp("1pt")
end


local function dirname(str)
    if str:match(".-/.-") then
        local name = string.gsub(str, "(.*/)(.*)", "%1")
        return name
    else
        return ''
    end
end


local function extract_includepaths(includepaths)
    includepaths = includepaths:explode(',')
    for i, path in ipairs(includepaths) do
        -- delete initial space (in case someone puts a space after the comma)
        includepaths[i] = path:gsub('^ ', '')
    end
    return includepaths
end


local fontdata = fonts.hashes.identifiers
local function fontinfo(id)
    local f = fontdata[id]
    if f then
        return f
    end
    return font.fonts[id]
end


local function locate(file, includepaths)
    local result = ly.CURRFILEDIR..file
    if not lfs.isfile(result) then result = file end
    if not lfs.isfile(result) then
        for _, d in ipairs(extract_includepaths(includepaths)) do
            result = d..'/'..file
            if lfs.isfile(result) then break end
        end
    end
    if not lfs.isfile(result) then result = kpse.find_file(file) end
    return result
end


local function mkdirs(str)
    local path = '.'
    for dir in string.gmatch(str, '([^%/]+)') do
        path = path .. '/' .. dir
        lfs.mkdir(path)
    end
end


local function __genorderedindex( t )
    local orderedIndex = {}
    for key in pairs(t) do
        table.insert( orderedIndex, key )
    end
    table.sort( orderedIndex )
    return orderedIndex
end
local function __orderednext(t, state)
    local key = nil
    if state == nil then
        t.__orderedIndex = __genorderedindex( t )
        key = t.__orderedIndex[1]
    else
        for i = 1, #t.__orderedIndex do
            if t.__orderedIndex[i] == state then
                key = t.__orderedIndex[i+1]
            end
        end
    end
    if key then
        return key, t[key]
    end
    t.__orderedIndex = nil
    return
end
local function orderedpairs(t)
    return __orderednext, t, nil
end


local function pt_to_staffspaces(pt, staffsize)
    local s_sp = staffsize / 4
    return pt / s_sp
end


local function set_fullpagestyle(style)
    if style then
        tex.sprint('\\includepdfset{pagecommand=\\thispagestyle{'..style..'}}')
    else
        tex.sprint('\\includepdfset{pagecommand=}')
    end
end


local function splitext(str, ext)
    if str:match(".-%..-") then
        local name = string.gsub(str, "(.*)(%." .. ext .. ")", "%1")
        return name
    else
        return str
    end
end


--[[ =============================== Classes =============================== ]]

local Score = {}
-- Score class

function Score:new(ly_code, options, input_file)
    local o = options or {}
    setmetatable(o, self)
    self.__index = self
    o.input_file = input_file
    o.ly_code = ly_code
    return o
end

function Score:apply_header()
    local header = [[
%%File header
\version "2.18.2"
]]
    if not self.fullpage then
        header = header..[[\include "lilypond-book-preamble.ly"]]..'\n'
    else
        header = header..
            string.format(
                [[#(set! paper-alist (cons '("lyluatexfmt" . (cons (* %s pt) (* %s pt))) paper-alist))]],
                self.paperwidth, self.paperheight
            )
    end
    header = header..
        string.format(
            [[
            #(define inside-lyluatex #t)

            #(set-global-staff-size %s)

            %%Score parameters

            \header {
              copyright = ""
              tagline = ##f
            }

            \paper{
            ]],
            self.staffsize
        )
    local lilymargin = ''
    if not self.fullpage then
        header = header..[[indent = 0\mm]]
    else
        local ppn = 'f'
        if self['print-page-number'] then ppn = 't' end
        header = header..string.format(
            [[#(set-paper-size "lyluatexfmt")
            print-page-number = ##%s
            print-first-page-number = ##t
            first-page-number = %s]],
            ppn, ly.PAGE
        )
        lilymargin = self:calc_margins()
    end
    header = header..
        string.format('\n'..
            [[
            two-sided = ##t
            line-width = %s\pt
            %s%s}
            %%Follows original score
            ]],
            self['line-width'], lilymargin..'\n', self:fonts()
        )
    self.ly_code =
        header..'\n'..self.ly_code
end

function Score:calc_margins()
    local tex_top = self['extra-top-margin'] + convert_unit((
        tex.sp('1in') + tex.dimen.voffset + tex.dimen.topmargin +
        tex.dimen.headheight + tex.dimen.headsep
    )..'sp')
    local tex_bottom = self['extra-bottom-margin'] + (
        convert_unit(tex.dimen.paperheight..'sp') -
        (tex_top + convert_unit(tex.dimen.textheight..'sp'))
    )
    local inner = convert_unit((
        tex.sp('1in') +
        tex.dimen.oddsidemargin +
        tex.dimen.hoffset
    )..'sp')
    if self.fullpagealign == 'crop' then
        return string.format([[
            top-margin = %s\pt
            bottom-margin = %s\pt
            inner-margin = %s\pt
            ]],
            tex_top, tex_bottom, inner
        )
    elseif self.fullpagealign == 'staffline' then
      local top_distance = pt_to_staffspaces(tex_top, self.staffsize) + 2
      local bottom_distance = pt_to_staffspaces(tex_bottom, self.staffsize) + 2
        return string.format([[
        top-margin = 0\pt
        bottom-margin = 0\pt
        inner-margin = %s\pt
        top-system-spacing =
        #'((basic-distance . %s)
           (minimum-distance . %s)
           (padding . 0)
           (stretchability . 0))
        top-markup-spacing =
        #'((basic-distance . %s)
           (minimum-distance . %s)
           (padding . 0)
           (stretchability . 0))
        last-bottom-spacing =
        #'((basic-distance . %s)
           (minimum-distance . %s)
           (padding . 0)
           (stretchability . 0))
        ]],
        inner,
        top_distance,
        top_distance,
        top_distance,
        top_distance,
        bottom_distance,
        bottom_distance
      )
    else
        err(
            [[
        Invalid argument for option 'fullpagealign'.
        Allowed: 'crop', 'staffline'.
        Given: %s
        ]],
            self.fullpagealign
        )
    end
end

function Score:calc_protrusion()
    --[[
      Determine the amount of space used to the left of the staff lines
      and generate a horizontal offset command.
    --]]
    local protrusion = ''
    local f = io.open(self.output..'.eps')
    --[[ The information we need is in the third line --]]
    f:read(); f:read()
    local bb_line = f:read()
    f:close()
    local cropped = bb_line:match('%d+')
    if cropped ~= 0 then
        protrusion = string.format('\\hspace*{-%spt}', cropped)
    end
    return protrusion
end

function Score:calc_properties()
    local staffsize = tonumber(self.staffsize)
    if staffsize == 0 then staffsize = fontinfo(font.current()).size/39321.6 end
    self.staffsize = staffsize
    local value
    for _, dimension in pairs({'line-width', 'paperwidth', 'paperheight'}) do
        value = self[dimension]
        if value == 'default' then
            if dimension == 'line-width' then value = tex.dimen.linewidth..'sp'
            else value = tex.dimen[dimension]..'sp'
            end
        end
        self[dimension] = convert_unit(value)
    end
    self['extra-top-margin'] = convert_unit(self['extra-top-margin'])
    self['extra-bottom-margin'] = convert_unit(self['extra-bottom-margin'])
    if self['current-font-as-main'] then
        self.rmfamily = self['current-font']
    end
    self.output = self:output_filename()
end

function Score:check_properties()
    for k, _ in orderedpairs(OPTIONS) do
        if not contains(OPTIONS[k], self[k]) and OPTIONS[k][2] then
            if type(OPTIONS[k][2]) == 'function' then OPTIONS[k][2](k, self[k])
            else
                err(
                        [[Unexpected value "%s" for option %s:
                        authorized values are "%s"
                        ]],
                        self[k], k, table.concat(OPTIONS[k], ', ')
                    )
            end
        end
    end
end

function Score:delete_intermediate_files()
  local i = io.open(self.output..'-systems.count', 'r')
  if i then
      local n = tonumber(i:read('*all'))
      i:close()
      for j = 1, n, 1 do
          os.remove(self.output..'-'..j..'.eps')
      end
      os.remove(self.output..'-systems.count')
      os.remove(self.output..'-systems.texi')
      os.remove(self.output..'.eps')
      os.remove(self.output..'.pdf')
  end
end

function Score:flatten_content(ly_code)
    --[[ Produce a flattend string from the original content,
        including referenced files (if they can be opened.
        Other files (from LilyPond's include path) are considered
        irrelevant for the purpose of a hashsum.) --]]
    local b, e, i, ly_file
    while true do
        b, e = ly_code:find('\\include%s*"[^"]*"', e)
        if not e then break
        else
            ly_file = ly_code:match('\\include%s*"([^"]*)"', b)
            ly_file = locate(ly_file, self.includepaths)
            if ly_file then
                i = io.open(ly_file, 'r')
                ly_code = ly_code:sub(1, b - 1)..
                    self:flatten_content(i:read('*a'))..
                    ly_code:sub(e + 1)
                i:close()
            end
        end
    end
    return ly_code
end

function Score:fonts()
    if self['pass-fonts'] then
        return string.format(
            [[
        #(define fonts
          (make-pango-font-tree "%s"
                                "%s"
                                "%s"
                                (/ staff-height pt 20)))
        ]],
            self.rmfamily,
            self.sffamily,
            self.ttfamily
        )
    else return '' end
end

function Score:is_compiled()
    if self.fullpage then
        return lfs.isfile(self.output..'.pdf')
    else
        local f = io.open(self.output..'-systems.tex')
        if f then
            local head = f:read("*line")
            return not (head == "% eof")
        else return false
        end
    end
end

function Score:output_filename()
    local properties = ''
    for k, _ in orderedpairs(OPTIONS) do
        if k ~= 'cleantmp' and self[k] and type(self[k]) ~= 'function' then
            properties = properties..'_'..k..'_'..self[k]
        end
    end
    local filename = md5.sumhexa(self:flatten_content(self.ly_code)..properties)
    self:write_to_filelist(filename)
    return self.tmpdir..'/'..filename
end

function Score:process()
    self:check_properties()
    self:calc_properties()
    local do_compile = not self:is_compiled()
    if do_compile then
        self:apply_header()
        self:run_lilypond()
    end
    self:write_tex(do_compile)
end

function Score:run_lilypond()
    mkdirs(dirname(self.output))
    local cmd = self.program.." "..
        "-dno-point-and-click "..
        "-djob-count=2 "..
        "-dno-delete-intermediate-files "
    if self.input_file then cmd = cmd.."-I "..lfs.currentdir()..'/'..self.input_file.." " end
    for _, dir in ipairs(extract_includepaths(self.includepaths)) do
        cmd = cmd.."-I "..dir:gsub('^./', lfs.currentdir()..'/').." "
    end
    cmd = cmd.."-o "..self.output.." -"
    local p = io.popen(cmd, 'w')
    p:write(self.ly_code)
    p:close()
end

function Score:write_tex(do_compile)
    if not self:is_compiled() then
      tex.print(
          [[
          \begin{quote}
          \fbox{Score failed to compile}
          \end{quote}

          ]]
      )
        err("\nScore failed to compile, please check LilyPond input.\n")
        --[[ ensure the score gets recompiled next time --]]
        os.remove(self.output..'-systems.tex')
    end
    --[[ Now we know there is a proper score --]]
    if self.fullpagestyle == 'default' then
        if self['print-page-number'] then
            set_fullpagestyle('empty')
        else set_fullpagestyle(nil)
        end
    else set_fullpagestyle(self.fullpagestyle)
    end
    local systems_file = io.open(self.output..'-systems.tex', 'r')
    if not systems_file then
        --[[ Fullpage score, use \includepdf ]]
        tex.sprint('\\includepdf[pages=-]{'..self.output..'}')
    else
        --[[ Fragment, use -systems.tex file]]
        local content = systems_file:read("*all")
        systems_file:close()
        if do_compile then
            --[[ new compilation, calculate protrusion
                 and update -systems.tex file]]
            local protrusion = self:calc_protrusion()
            local texoutput, _ = content:gsub([[\includegraphics{]],
                [[\noindent]]..' '..protrusion..[[\includegraphics{]]..dirname(self.output))
            tex.sprint(texoutput:explode('\n'))
            local f = io.open(self.output..'-systems.tex', 'w')
            f:write(texoutput)
            f:close()
            self:delete_intermediate_files()
        else
            -- simply reuse existing -systems.tex file
            tex.sprint(content:explode('\n'))
        end
    end
end

function Score:write_to_filelist(filename)
    local f = io.open(FILELIST, 'a')
    f:write(filename, '\t', self.input_file or '', '\n')
    f:close()
end


--[[ ========================== Public functions ========================== ]]

function ly.clean_tmp_dir()
    local hash, file_is_used
    local hash_list = {}
    for file in lfs.dir(Score.tmpdir) do
        if file:sub(-5, -1) == '.list' then
            local i = io.open(Score.tmpdir..'/'..file)
            for _, line in ipairs(i:read('*a'):explode('\n')) do
                hash = line:explode('\t')[1]
                if hash ~= '' then table.insert(hash_list, hash) end
            end
            i:close()
        end
    end
    for file in lfs.dir(Score.tmpdir) do
        file_is_used = false
        if file ~= '.' and file ~= '..' and file:sub(-5, -1) ~= '.list' then
            for _, lhash in ipairs(hash_list) do
                if file:find(lhash) then
                    file_is_used = true
                    break
                end
            end
            if not file_is_used then
                os.remove(Score.tmpdir..'/'..file)
            end
        end
    end
end


function ly.conclusion_text()
    print(
        string.format('\n'..[[
            Output written on %s.pdf.
            Transcript written on %s.log.]],
            tex.jobname, tex.jobname
        )
    )
end


function ly.declare_package_options(options)
    OPTIONS = options
    for k, v in pairs(options) do
        tex.sprint(string.format([[\DeclareStringOption[%s]{%s}%%]], v[1], k))
    end
    tex.sprint([[\ProcessKeyvalOptions*]])
    mkdirs(options.tmpdir[1])
    FILELIST = options.tmpdir[1]..'/'..splitext(status.log_name, 'log')..'.list'
    os.remove(FILELIST)
end


function ly.file(input_file, options)
    options = ly.set_local_options(options)
    local file = input_file
    --[[ Here, we only take in account global option includepaths,
    as it really doesn't mean anything as a local option. ]]
    input_file = locate(file, Score.includepaths)
    if not input_file then err("File %s.ly doesn't exist.", file) end
    local i = io.open(input_file, 'r')
    ly.score = Score:new(i:read('*a'), options, input_file)
    i:close()
end


function ly.fragment(ly_code, options)
    options = ly.set_local_options(options)
    ly.score = Score:new(
        ly_code:gsub('\\par ', '\n'):gsub('\\([^%s]*) %-([^%s])', '\\%1-%2'),
        options
    )
end


function ly.get_font_family(font_id)
    return fontinfo(font_id).shared.rawdata.metadata['familyname']
end


function ly.get_option(opt)
    return Score[opt]
end


function ly.newpage_if_fullpage()
    if ly.score.fullpage then tex.sprint([[\newpage]]) end
end


function ly.set_local_options(opts)
    local options = {}
    local a, b, c, d
    while true do
        a, b = opts:find('%w[^=]+=', d)
        c, d = opts:find('{{{%w*}}}', d)
        if not d then break end
        local k, v = opts:sub(a, b - 1), opts:sub(c + 3, d - 3)
        if v == 'false' then v = false end
        if v ~= '' then options[k] = v end
    end
    return options
end


function ly.is_dim (dim, value)
    local n, u = value:match('%d*%.?%d*'), value:match('%a+')
    if tonumber(value) or n and contains(TEX_UNITS, u) then return true
    else err(
        [[Unexpected value "%s" for dimension %s:
        should be either a number (for example "12"), or a number with unit, without space ("12pt")
        ]],
        value, dim
    )
    end
end


function ly.set_default_options()
    for k, _ in pairs(OPTIONS) do
        tex.sprint(
            string.format(
                [[
                \directlua{
                  ly.set_property('%s', '\luatexluaescapestring{\lyluatex@%s}')
                }]], k, k
            )
        )
    end
end


function ly.set_property(name, value)
    if value == 'false' then value = false end
    Score[name] = value
end


return ly
