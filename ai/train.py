import torch
import torch.nn as nn

import torchvision.transforms.v2 as v2
from torchvision.datasets import MNIST

from torch.utils.data import random_split
from torch.utils.data import DataLoader

import matplotlib.pyplot as plt


def load_minist_ds() -> MNIST:
    transform = v2.Compose([
        v2.ToImage(),
        v2.ToDtype(torch.float32, scale=True),
    ])
    ds = MNIST(root='./ai/data/', train=True,
               download=True, transform=transform)
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
