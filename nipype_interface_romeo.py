import os
from nipype.interfaces.base import CommandLine, traits, TraitedSpec, File, CommandLineInputSpec, OutputMultiPath
from nipype.interfaces.base.traits_extension import isdefined
from nipype.utils.filemanip import fname_presuffix, split_filename

#phase_dir = ARGS[1]
#TEs = [parse(Float64, x) for x in split(ARGS[2], ',')]
#weights_threshold = parse(Int, ARGS[3])
#TEs = [5.84,10.63,15.42,20.21,25]
#out_dir = ARGS[4]

def gen_filename(fname, suffix, newpath, use_ext=True):
    return fname_presuffix(
        fname=fname,
        suffix=suffix,
        newpath=newpath,
        use_ext=use_ext
    )

class RomeoInputSpec(CommandLineInputSpec):
    in_file = File(
        exists=True,
        desc='Phase image',
        mandatory=True,
        argstr="%s",
        position=0
    )
    echo_times = traits.List(
        minlen=2,
        desc='Echo times',
        mandatory=True,
        argstr="%s",
        position=1
    )
    weights_threshold = traits.Int(
        default_value=300,
        desc='Weights threshold',
        mandatory=True,
        argstr="%s",
        position=2
    )
    out_file = File(
        argstr="%s",
        name_source=['in_file'],
        name_template='%s_romeomask.nii',
        position=3
    )


class RomeoOutputSpec(TraitedSpec):
    out_file = OutputMultiPath(
        File(desc='Output mask')
    )


class RomeoInterface(CommandLine):
    input_spec = RomeoInputSpec
    output_spec = RomeoOutputSpec
    _cmd = "romeo_mask.jl"

    def __init__(self, **inputs):
        super(RomeoInterface, self).__init__(**inputs)

    def _list_outputs(self):
        outputs = self.output_spec().get()

        # NOTE: workaround for multi-echo data - the QSM node requires one mask per phase image
        pth, fname, ext = split_filename(self.inputs.in_file)
        outfile = gen_filename(
            fname=fname + "_romeomask",
            suffix=ext,
            newpath=os.getcwd()
        )
        outputs['out_file'] = [outfile for x in range(len(self.inputs.echo_times))]

        return outputs

    def _format_arg(self, name, spec, value):
        if name == 'echo_times':
            value = str(value)
            value = value.replace(' ', '')
            value = value.replace('[', '').replace(']', '')
            return spec.argstr%value
        return super(RomeoInterface, self)._format_arg(name, spec, value)