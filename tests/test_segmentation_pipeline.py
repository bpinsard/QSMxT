#!/usr/bin/env pytest
import os
import tempfile
import pytest

import numpy as np
import qsm_forward

import run_2_qsm as qsm

from scripts.sys_cmd import sys_cmd
from tests.utils import *

run_workflows = True

@pytest.fixture
def bids_dir_public():
    tmp_dir = tempfile.gettempdir()
    bids_dir = os.path.join(tmp_dir, "bids-public")
    if not os.path.exists(bids_dir):

        head_phantom_maps_dir = os.path.join(tmp_dir, 'head-phantom-maps')
        if not os.path.exists(head_phantom_maps_dir):
            if not os.path.exists(os.path.join(tmp_dir, 'head-phantom-maps.tar')):
                download_from_rdm(
                    remote_path="QSMFUNCTOR-Q0748/qsm-challenge-and-head-phantom/head-phantom-maps.tar",
                    local_path=os.path.join(tmp_dir, "head-phantom-maps.tar")
                )

            sys_cmd(f"tar xf {os.path.join(tmp_dir, 'head-phantom-maps.tar')} -C {tmp_dir}")
            sys_cmd(f"rm {os.path.join(tmp_dir, 'head-phantom-maps.tar')}")

        tissue_params = qsm_forward.TissueParams(os.path.join(tmp_dir, 'head-phantom-maps'))
        
        recon_params_all = [
            qsm_forward.ReconParams(voxel_size=np.array([1.0, 1.0, 1.0]), session=session, TEs=TEs, TR=TR, flip_angle=flip_angle, weighting_suffix=weighting_suffix, export_phase=export_phase)
            for (session, TEs, TR, flip_angle, weighting_suffix, export_phase) in [
                ("1", np.array([3.5e-3]), 7.5e-3, 40, "T1w", False),
                ("1", np.array([0.004, 0.012]), 0.05, 15, "T2starw", True),
            ]
        ]

        bids_dir = os.path.join(tmp_dir, "bids-public")
        for recon_params in recon_params_all:
            qsm_forward.generate_bids(tissue_params=tissue_params, recon_params=recon_params, bids_dir=bids_dir)
        sys_cmd(f"rm {head_phantom_maps_dir}")

    return bids_dir

@pytest.mark.parametrize("init_workflow, run_workflow, run_args", [
    (True, run_workflows, None)
])
def test_segmentation(bids_dir_public, init_workflow, run_workflow, run_args):
    print(f"=== TESTING SEGMENTATION PIPELINE ===")
    os.makedirs(os.path.join(tempfile.gettempdir(), "public-outputs"), exist_ok=True)

    # run pipeline and specifically choose magnitude-based masking
    args = qsm.process_args(qsm.parse_args([
        bids_dir_public,
        os.path.join(tempfile.gettempdir(), "output"),
        "--do_qsm", "no",
        "--do_segmentation", "yes",
        "--auto_yes",
        "--debug",
    ]))
    
    # create the workflow and run - it should fall back to phase-based masking with a warning
    workflow(args, init_workflow, run_workflow, run_args, "segmentation", delete_workflow=True, upload_png=False)
