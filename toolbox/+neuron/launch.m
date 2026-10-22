function n = launch()
% Start a NEURON session.
%   n = neuron.launch()
% Set the path for HOC_LIBRARY_PATH, environment variable
mFilePath = mfilename('fullpath');
hocLibraryPath = string(fileparts(fileparts(mFilePath)));
hocLibraryPath = fullfile(hocLibraryPath, "nrn", "share", "nrn", "lib", "hoc");
% hocLibraryPath = hocLibraryPath + filesep + "nrn" + filesep + "share" +...
%     filesep + "nrn" + filesep + "lib" +  filesep + "hoc";
setenv("HOC_LIBRARY_PATH", hocLibraryPath);
nrnHome = fullfile(fileparts(fileparts(mFilePath)),"nrn");
setenv("NRNHOME", nrnHome)
neuron_api();
n = neuron.Session.instance();
end
