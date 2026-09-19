import torch
import torch.nn as nn

import matplotlib.pyplot as plt


import torchvision
import torchvision.transforms.v2 as v2
from torchvision.datasets import MNIST

from torch.utils.data import random_split
from torch.utils.data import DataLoader

import torch.nn.functional as F

# Note: consider 'ds' and 'dataset' as the same


def load_minist_ds() -> MNIST:
    transform = v2.Compose([
        v2.ToImage(),
        v2.ToDtype(torch.float32, scale=True),
    ])
    ds = MNIST(root='.', train=True, download=True, transform=transform)
    print(f"This dataset has {len(ds)} labels")

    return ds


def ds_view_label(ds: MNIST, idx: int) -> None:
    img, label = ds[idx]
    plt.imshow(img.squeeze(), cmap='gray')
    plt.title(f"Label: {label}")
    plt.savefig(f"sample_{idx}.png")
    plt.close()
    print(label)


def train(model: nn.Module, ds: MNIST, epochs: int = 20) -> None:
    train_data, validation_data = random_split(ds, [50000, 10000])

    train_loader = DataLoader(train_data, batch_size=128, shuffle=True)
    val_loader = DataLoader(validation_data, batch_size=128, shuffle=False)

    criterion = nn.CrossEntropyLoss()
    optimizer = torch.optim.Adam(model.parameters(), lr=1e-3)

    model.train()

    for epoch in range(epochs):
        running_loss = 0.0

        for images, labels in train_loader:
            optimizer.zero_grad()
            outputs = model(images)
            loss = criterion(outputs, labels)
            loss.backward()
            optimizer.step()
            running_loss += loss.item()

        avg_loss = running_loss / len(train_loader)
        print(f"Epoch [{epoch + 1}/{epochs}] - Loss: {avg_loss:.4f}")


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
        # x = x.reshape(-1, 784)
        # self.out = self.liear(x)
        return self.net(x)


if __name__ == '__main__':
    # model = Model([784, 16, 10])
    model = Model([784, 256, 64, 10])

    print("Viewing the model:")
    print(model)

    print("Loading Mnist dataset...")
    dataset = load_minist_ds()

    print("Viewing labels:")
    max_range = 3
    print("...")

    for i in range(max_range):
        print(f"{i}: ", end='')
        ds_view_label(dataset, i)

    print("Start train:")
    train(model, dataset)


'''
Source: 
- https://www.kaggle.com/code/geekysaint/solving-mnist-using-pytorch
- https://docs.pytorch.org/tutorials/beginner/basics/intro.html
'''
