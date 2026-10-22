function [mechLib, special] = nrnmech_makefile(target, options)
% Build a NEURON mechanism library from mod files.
%   [mechLib, special] = neuron.nrnmech_makefile()
%   [mechLib, special] = neuron.nrnmech_makefile(target, ModFiles=files, ...)
% MATLAB port of nrn/bin/nrnmech_makefile, normally driven by
% neuron.nrnivmodl. target is "special" (default), "mechlib" or
% "install". The build runs in BuildFolder (default pwd, the x86_64
% folder), which must already contain mod_func.cpp. Options:
%   ModFiles       absolute paths of the mod files (MODOBJFILES)
%   ModFolder      folders whose *.mod files are all built, in addition
%                  to ModFiles
%   CFiles        absolute paths of extra C files
%   IncludeFlags   extra compiler flags (UserINCFLAGS)
%   LoadFlags      extra linker flags (UserLDFLAGS)
%   LinkCoreNEURON link against libcorenrnmech (LinkCoreNEURON)
%   DestDir        install destination for the "install" target (DESTDIR)
%   Root           NEURON installation (ROOT), default NRNHOME
% Like make, mod files and objects are only rebuilt when out of date;
% mod_func.o, the shared library and special are always rebuilt.
arguments
    target (1,1) string {mustBeMember(target, ["special", "mechlib", "install"])} = "special"
    options.ModFiles string = string.empty
    options.ModFolder string {mustBeFolder} = string.empty
    options.CFiles string = string.empty
    options.BuildFolder (1,1) string = string(pwd)
    options.IncludeFlags (1,1) string = ""
    options.LoadFlags (1,1) string = ""
    options.LinkCoreNEURON (1,1) logical = false
    options.DestDir (1,1) string = ""
    options.Root (1,1) string = string(getenv("NRNHOME"))
end

if options.Root == ""
    error("Neuron Toolbox: NRNHOME is not set; call neuron.launch() first or pass Root.");
end
if target == "install" && options.DestDir == ""
    error("Neuron Toolbox: the install target requires DestDir.");
end

% Install dirs.
binDir = fullfile(options.Root, "bin");
libDir = fullfile(options.Root, "lib");
incDir = fullfile(options.Root, "include");
dataDir = fullfile(options.Root, "share", "nrn");
nocmodl = fullfile(binDir, "nocmodl");

% Walk through each ModFolder and add its mod files.
modFiles = options.ModFiles(:);
for i = 1:numel(options.ModFolder)
    listing = dir(fullfile(options.ModFolder(i), "*.mod"));
    if isempty(listing)
        error("Neuron Toolbox: no mod files found in %s.", options.ModFolder(i));
    end
    modFiles = [modFiles; fullfile(string({listing.folder}'), string({listing.name}'))]; %#ok<AGROW>
end

buildDir = options.BuildFolder;
startDir = pwd;
cd(buildDir);
restoreDir = onCleanup(@() cd(startDir));

% Compilers; CXX and CC are used when set in the environment.
cxx = string(getenv("CXX"));
if cxx == ""
    cxx = "c++";
end
cc = string(getenv("CC"));
if cc == ""
    cc = "cc";
end
cxxFlags = "-O2 -std=c++17";
defs = "-DUSE_PYTHON -DNRN_ENABLE_THREADS -DCORENRN_BUILD=0 -DNRNPYTHON_DYNAMICLOAD " + ...
    "-DMPI_NO_CPPBIND=1 -DOMPI_SKIP_MPICXX=1 -DMPICH_SKIP_MPICXX=1 -DHAVE_CONFIG_H";
cxxCompile = cxx + " " + cxxFlags + " " + defs;
cCompile = cc + " -O2 -std=c17 " + defs;
cxxLinkExe = cxx + " " + cxxFlags + " -Wl,--unresolved-symbols=ignore-all";
cxxLinkShared = cxx + " " + cxxFlags + " -shared -fPIC";
includes = "-I. " + options.IncludeFlags + " -I" + q(incDir);
ldFlags = options.LoadFlags;
nrnLibFlags = "-L" + q(libDir) + " -lnrniv";
nrnLibRpathFlags = "-Wl,-rpath," + q(libDir);
extraLdFlags = "";
if options.LinkCoreNEURON
    extraLdFlags = "-L" + q(libDir) + " -lcorenrnmech -lgomp -ldl";
end

% $ORIGIN (@loader_path on macOS) unless installing into DestDir.
if ismac
    origin = "@loader_path";
    soname = "-Wl,-install_name,@rpath/libnrnmech.so";
else
    origin = "$ORIGIN";
    soname = "-Wl,-soname,libnrnmech.so";
end
destDirRpath = origin;
if options.DestDir ~= ""
    destDirRpath = fullfile(options.DestDir, "lib");
end

% Rules from makemod2c_inc: mod -> cpp -> o.
objs = strings(0, 1);
for i = 1:numel(modFiles)
    modFile = modFiles(i);
    [modDir, baseName] = fileparts(modFile);
    cppFile = fullfile(buildDir, baseName + ".cpp");
    objFile = "./" + baseName + ".o";
    if isStale(cppFile, [modFile, nocmodl])
        fprintf(" -> NMODL %s\n", modFile);
        % Run nocmodl from the mod file's folder so relative INCLUDEs resolve.
        cd(modDir);
        neuron.transpileModFile(baseName + ".mod", OutputFolder=buildDir);
        cd(buildDir);
    end
    if isStale(objFile, cppFile)
        fprintf(" -> Compiling %s\n", cppFile);
        runCommand(cxxCompile + " -I" + q(modDir) + " " + includes + " -fPIC -c " + ...
            q(cppFile) + " -o " + q(objFile));
    end
    objs(end+1, 1) = objFile; %#ok<AGROW>
end
for i = 1:numel(options.CFiles)
    [cDir, cName, cExt] = fileparts(options.CFiles(i));
    objFile = "./" + cName + cExt + ".o";
    if isStale(objFile, options.CFiles(i))
        fprintf(" -> Compiling %s\n", options.CFiles(i));
        runCommand(cCompile + " -I" + q(cDir) + " " + includes + " -fPIC -c " + ...
            q(options.CFiles(i)) + " -o " + q(objFile));
    end
    objs(end+1, 1) = objFile; %#ok<AGROW>
end

% mod_func.o: mod_func.cpp. Always rebuilt since nrnivmodl regenerates
% mod_func.cpp on every call and file times only have 1 s resolution.
if ~isfile("mod_func.cpp")
    error("Neuron Toolbox: mod_func.cpp not found in %s.", buildDir);
end
fprintf(" -> Compiling mod_func.cpp\n");
runCommand(cxxCompile + " " + includes + " -fPIC -c mod_func.cpp -o mod_func.o");

% mech_lib_shared (build_always). The .tmp output avoids nvc++ error:
% input file 'libnrnmech.so' is the same as output file.
mechLib = fullfile(buildDir, "libnrnmech.so");
fprintf(" => LINKING shared library ""%s""\n", mechLib);
runCommand(cxxLinkShared + " -I" + q(incDir) + " -o libnrnmech.so.tmp " + soname + ...
    " ./mod_func.o " + join([objs; ""], " ") + nrnLibFlags + " " + nrnLibRpathFlags + ...
    " " + ldFlags);
movefile("libnrnmech.so.tmp", mechLib, "f");

% special: take the main and link with nrnmech. RPATH is set for
% destDirRpath and the NEURON lib folder.
special = fullfile(buildDir, "special");
if target ~= "mechlib"
    fprintf(" => LINKING executable ""%s"" LDFLAGS are: %s\n", special, ldFlags);
    runCommand(cxxLinkExe + " -I" + q(incDir) + " -I" + q(fullfile(incDir, "nrncvode")) + ...
        " -DAUTO_DLOPEN_NRNMECH=0 " + q(fullfile(dataDir, "nrnmain.cpp")) + ...
        " -o " + q(special) + " -L. -lnrnmech " + nrnLibFlags + " -lnrnmech" + ...
        " -Wl,-rpath,'" + destDirRpath + "' " + nrnLibRpathFlags + " " + ldFlags + ...
        " " + extraLdFlags);
end

% install: copy the library and special into DestDir.
if target == "install"
    for sub = ["bin", "lib"]
        if ~isfolder(fullfile(options.DestDir, sub))
            mkdir(fullfile(options.DestDir, sub));
        end
    end
    copyfile(mechLib, fullfile(options.DestDir, "lib"), "f");
    copyfile(special, fullfile(options.DestDir, "bin"), "f");
    mechLib = fullfile(options.DestDir, "lib", "libnrnmech.so");
    special = fullfile(options.DestDir, "bin", "special");
end
end

function tf = isStale(target, deps)
% True when target is missing or older than any existing dependency.
t = dir(target);
if isempty(t)
    tf = true;
    return
end
tf = false;
for d = deps(:)'
    info = dir(d);
    if ~isempty(info) && info.datenum > t.datenum
        tf = true;
        return
    end
end
end

function s = q(s)
% Double-quote a path for the shell.
s = """" + s + """";
end

function runCommand(cmd)
% Run a shell command and raise an error with its output on failure.
[status, output] = system(cmd);
if status ~= 0
    error("Neuron Toolbox: command failed:\n%s\n%s", cmd, output);
end
end
