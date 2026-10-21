#!/usr/bin/env python3
"""Convert KAIR's MIT-licensed ffdnet_color.pth into the bundled, offline Core ML model.

Architecture adapted from cszn/KAIR/models/network_ffdnet.py (Copyright 2019 Kai Zhang).
The checkpoint must come from https://github.com/cszn/KAIR/releases/tag/v1.0.
"""
import argparse
import hashlib
from pathlib import Path

import coremltools as ct
import numpy as np
import torch
from torch import nn

ROOT = Path(__file__).resolve().parents[2]


class FFDNetColor(nn.Module):
    def __init__(self):
        super().__init__()
        layers = [nn.Conv2d(13, 96, 3, padding=1), nn.ReLU()]
        for _ in range(10):
            layers += [nn.Conv2d(96, 96, 3, padding=1), nn.ReLU()]
        layers += [nn.Conv2d(96, 12, 3, padding=1)]
        self.model = nn.Sequential(*layers)

    def forward(self, noisy, sigma):
        # Spell out the channel shuffle so the single-file NeuralNetwork format can represent it.
        down = noisy.reshape(1, 3, 128, 2, 128, 2).permute(0, 1, 3, 5, 2, 4).reshape(1, 12, 128, 128)
        noise_map = sigma.repeat(1, 1, 128, 128)
        clean = self.model(torch.cat((down, noise_map), 1))
        return clean.reshape(1, 3, 2, 2, 128, 128).permute(0, 1, 4, 2, 5, 3).reshape(1, 3, 256, 256)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--weights', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=ROOT / 'Compositor/Resources/FFDNetColor.mlmodel')
    args = parser.parse_args()
    digest = hashlib.sha256(args.weights.read_bytes()).hexdigest()
    if digest != '286f04f7e3a20254c067ba95efb5d3339f4fc8a09a365a93cd469184d4cdb279':
        raise RuntimeError('Checkpoint differs from the verified KAIR v1.0 ffdnet_color.pth')
    print('Checkpoint SHA-256:', digest, flush=True)
    torch.set_num_threads(2)
    net = FFDNetColor().eval()
    net.load_state_dict(torch.load(args.weights, map_location='cpu', weights_only=True), strict=True)
    rng = np.random.default_rng(42)
    noisy = rng.uniform(0, 1, (1, 3, 256, 256)).astype(np.float32)
    sigma = np.full((1, 1, 1, 1), 25 / 255, dtype=np.float32)
    example = (torch.from_numpy(noisy), torch.from_numpy(sigma))
    with torch.no_grad():
        traced = torch.jit.trace(net, example)
        reference = net(*example).numpy()
    model = ct.convert(
        traced, convert_to='neuralnetwork', minimum_deployment_target=ct.target.macOS11,
        inputs=[ct.TensorType(name='noisy', shape=noisy.shape), ct.TensorType(name='sigma', shape=sigma.shape)],
        outputs=[ct.TensorType(name='clean')], compute_units=ct.ComputeUnit.CPU_ONLY,
    )
    model.author = 'Kai Zhang; Core ML conversion by Compositor-ZH contributors'
    model.license = 'MIT; see LICENSE-FFDNet.txt'
    model.short_description = 'FFDNet color photo denoising, sRGB float RGB, 256-pixel tiles.'
    model.user_defined_metadata['source'] = 'https://github.com/cszn/KAIR'
    model.user_defined_metadata['checkpoint_sha256'] = digest
    model.input_description['noisy'] = 'Straight sRGB in [0,1], NCHW [1,3,256,256].'
    model.input_description['sigma'] = 'Noise standard deviation in [0,75/255], [1,1,1,1].'
    model.output_description['clean'] = 'Denoised straight sRGB, NCHW [1,3,256,256].'
    actual = model.predict({'noisy': noisy, 'sigma': sigma})['clean']
    error = float(np.max(np.abs(actual - reference)))
    if error > 0.002:
        raise RuntimeError(f'Core ML/PyTorch conversion mismatch: {error}')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    model.save(str(args.output))
    print(f'Core ML/PyTorch max error: {error:.8f}; saved {args.output}', flush=True)


if __name__ == '__main__':
    main()
