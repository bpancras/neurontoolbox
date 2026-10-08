function n = launch()
% Start a NEURON session.
%   n = neuron.launch()
% Set the path for HOC_LIBRARY_PATH, environment variable
mFilePath = mfilename('fullpath');
hocLibraryPath = string(fileparts(fileparts(mFilePath)));
hocLibraryPath = hocLibraryPath + filesep + "nrn" + filesep + "share" +...
    filesep + "nrn" + filesep + "lib" +  filesep + "hoc";
setenv("HOC_LIBRARY_PATH", hocLibraryPath);
neuron_api();
n = neuron.Session.instance();
end
