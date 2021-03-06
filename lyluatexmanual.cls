%Lyluatex LaTeX class for the manual.
%
% Copyright (C) 2015-2018 jperon and others (see CONTRIBUTORS.md)
% License: MIT
% This file is part of lyluatex.

\NeedsTeXFormat{LaTeX2e}
\ProvidesClass{lyluatexmanual}[2018/03/12 v1.0b]  %%LYLUATEX_DATE LYLUATEX_VERSION

\LoadClass{lyluatexbase}

\RequirePackage{fontspec}
\RequirePackage{microtype}
\RequirePackage{libertine}
\setmonofont[Scale=MatchLowercase,StylisticSet=1]{InconsolataN}
\defaultfontfeatures{
	Ligatures=TeX,
	Scale=MatchLowercase,
	Numbers=Proportional,
	Numbers=OldStyle
}
\frenchspacing

\RequirePackage{makeidx}
\makeindex

\newcommand{\linkexample}[2]{
    \addcontentsline{toc}{subsection}{#2}
    \hypertarget{#1}{}
}
