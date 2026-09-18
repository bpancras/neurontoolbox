function plan = buildfile
import matlab.buildtool.tasks.MexTask
import matlab.buildtool.tasks.CleanTask

plan = buildplan(localfunctions);

% Add a task to delete outputs and traces
plan("clean") = CleanTask;

% Build the neuron_api MEX file from C++ source
cppSource = ["source/neuron_api.cpp"];
mexOptions = ["COMPFLAGS=$COMPFLAGS /std:c++17"...
    "-Itoolbox/nrn/include/"];
plan("mex") = MexTask.forEachFile(cppSource, "toolbox/", ...
    Options=mexOptions);
end


function libmodelregTask(~)
% Compile libmodelreg
status = system("cc -shared -fPIC -o ./toolbox/libmodelreg.so ./source/modl_reg.c");
end