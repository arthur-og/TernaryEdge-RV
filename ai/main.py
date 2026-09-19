from train import load_mnist_ds, ds_view_label, train
from model import Model


def main() -> None:
    # model = Model([784, 16, 10])
    model = Model([784, 256, 64, 10])

    print("Viewing the model:")
    print(model)

    print("Loading Mnist dataset...")
    dataset = load_mnist_ds()

    print("Viewing labels:")
    max_range = 3
    print("...")

    for i in range(max_range):
        print(f"{i}: ", end='')
        ds_view_label(dataset, i)

    print("Start train:")
    train(model, dataset)


if __name__ == '__main__':
    main()

'''
Source: 
- https://www.kaggle.com/code/geekysaint/solving-mnist-using-pytorch
- https://docs.pytorch.org/tutorials/beginner/basics/intro.html
'''
