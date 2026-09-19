import torch
import torch.nn as nn


class Model(nn.Module):
    def __init__(self, dims: list[int]):
        super().__init__()

        layers = []

        for i in range(len(dims) - 1):
            layers.append(nn.Linear(dims[i], dims[i+1]))

            if i < len(dims)-2:
                layers.append(nn.ReLU())

        self.net = nn.Sequential(
            nn.Flatten(),
            *layers)

        '''
        example:
            net = nn.Sequential(
                nn.Linear(10, 32),
                nn.ReLU(),
                nn.Linear(32, 1)
            )
        '''

    def forward(self, x) -> torch.Tensor:
        return self.net(x)
