function [mechLib, special] = nrnmech_makefile(options)
% Build a NEURON mechanism library from mod files.
%   [mechLib, special] = neuron.nrnmech_makefile()
%   [mechLib, special] = neuron.nrnmech_makefile(target, ModFiles=files, ...)
% MATLAB port of nrn/bin/nrnmech_makefile, normally driven by
% neuron.nrnivmodl. target is "special" (default), "mechlib" or
% "install". Outputs are written to BuildFolder (default pwd, the x86_64
% folder), which must already contain mod_func.cpp. Options:
%   ModFiles       absolute paths of the mod files (MODOBJFILES)
%   ModFolder      folders whose *.mod files are all built, in addition
%                  to ModFiles
%   CFiles        absolute paths of extra C files
%   IncludeFlags   extra compiler flags (UserINCFLAGS)
%   LoadFlags      extra linker flags (UserLDFLAGS)
%   LinkCoreNEURON link against libcorenrnmech (LinkCoreNEURON)
% Like make, mod files and objects are only rebuilt when out of date;
% mod_func.o, the shared library and special are always rebuilt. The
% NEURON installation (ROOT) is taken from NRNHOME.
arguments
    % target (1,1) string {mustBeMember(target, ["special", "mechlib", "install"])} = "special"
    options.ModFiles string = string.empty
    options.ModFolder string {mustBeFolder} = string.empty
    options.CFiles string = string.empty
    options.BuildFolder (1,1) string = string(pwd)
    options.IncludeFlags (1,1) string = ""
    options.LoadFlags (1,1) string = ""
    options.LinkCoreNEURON (1,1) logical = false
end

NRNRoot = string(getenv("NRNHOME"));
if NRNRoot == ""
    error("Neuron Toolbox: NRNHOME is not set; call neuron.launch() first.");
end
% if target == "install" && options.DestDir == ""
%     error("Neuron Toolbox: the install target requires DestDir.");
% end

% Install dirs.
binDir = fullfile(NRNRoot, "bin");
libDir = fullfile(NRNRoot, "lib");
incDir = fullfile(NRNRoot, "include");
dataDir = fullfile(NRNRoot, "share", "nrn");
nocmodl = fullfile(binDir, "nocmodl");
nrnUnits = fullfile(dataDir, "lib", "nrnunits.lib");

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

% Double-quote a path for the shell.
q = @(s) """" + s + """";

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
includes = "-I" + q(buildDir) + " " + options.IncludeFlags + " -I" + q(incDir);
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

mechLib = fullfile(buildDir, "libnrnmech.so");
mechLibTmp = mechLib + ".tmp";
try
    % Rules from makemod2c_inc: mod -> cpp -> o.
    objs = strings(0, 1);
    for i = 1:numel(modFiles)
        modFile = modFiles(i);
        [modDir, baseName] = fileparts(modFile);
        cppFile = fullfile(buildDir, baseName + ".cpp");
        objFile = fullfile(buildDir, baseName + ".o");

        fprintf(" => NMODL %s\n", modFile);
        % nocmodl resolves relative INCLUDEs against the mod file's folder.
        cmd = "MODLUNIT=" + q(nrnUnits) + " " + q(nocmodl) + " " + q(modFile) + ...
            " -o " + q(buildDir);
        [status, output] = system(cmd);
        if (status ~= 0)
            error("Neuron Toolbox: command failed:\n%s\n%s", cmd, output);
        end
        fprintf(" => Compiling %s\n", cppFile);
        cmd = cxxCompile + " -I" + q(modDir) + " " + includes + " -fPIC -c " + ...
            q(cppFile) + " -o " + q(objFile);
        [status, output] = system(cmd);
        if (status ~= 0)
            error("Neuron Toolbox: command failed:\n%s\n%s", cmd, output);
        end
        objs(end+1, 1) = q(objFile); %#ok<AGROW>
    end
    for i = 1:numel(options.CFiles)
        [cDir, cName, cExt] = fileparts(options.CFiles(i));
        objFile = fullfile(buildDir, cName + cExt + ".o");
        fprintf(" => Compiling %s\n", options.CFiles(i));
        cmd = cCompile + " -I" + q(cDir) + " " + includes + " -fPIC -c " + ...
            q(options.CFiles(i)) + " -o " + q(objFile);
        [status, output] = system(cmd);
        if (status ~= 0)
            error("Neuron Toolbox: command failed:\n%s\n%s", cmd, output);
        end
        objs(end+1, 1) = q(objFile); %#ok<AGROW>
    end

    % mod_func.o: mod_func.cpp. Always rebuilt since nrnivmodl regenerates
    % mod_func.cpp on every call and file times only have 1 s resolution.
    modFuncCpp = fullfile(buildDir, "mod_func.cpp");
    modFuncObj = fullfile(buildDir, "mod_func.o");
    if ~isfile(modFuncCpp)
        error("Neuron Toolbox: mod_func.cpp not found in %s.", buildDir);
    end
    fprintf(" => Compiling mod_func.cpp\n");
    cmd = cxxCompile + " " + includes + " -fPIC -c " + q(modFuncCpp) + " -o " + q(modFuncObj);
    [status, output] = system(cmd);
    if (status ~= 0)
        error("Neuron Toolbox: command failed:\n%s\n%s", cmd, output);
    end

    % mech_lib_shared (build_always). The .tmp output avoids nvc++ error:
    % input file 'libnrnmech.so' is the same as output file.
    fprintf(" => LINKING shared library ""%s""\n", mechLib);
    cmd = cxxLinkShared + " -I" + q(incDir) + " -o " + q(mechLibTmp) + " " + soname + ...
        " " + q(modFuncObj) + " " + join([objs; ""], " ") + nrnLibFlags + " " + nrnLibRpathFlags + ...
        " " + ldFlags;
    [status, output] = system(cmd);
    if (status ~= 0)
        error("Neuron Toolbox: command failed:\n%s\n%s", cmd, output);
    end
    movefile(mechLibTmp, mechLib, "f");
catch ME
    % Remove a partially linked library before passing the error on.
    if isfile(mechLibTmp)
        delete(mechLibTmp);
    end
    rethrow(ME);
end
end

