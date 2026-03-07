conda create -n nw python=3
conda activate nw

conda install -c conda-forge graph-tool
conda update --all
conda install pandas requests tqdm seaborn scikit-learn

pip install git+https://github.com/vikramr2/python-mincut
pip install igraph leidenalg networkit

cd constrained-clustering
sh easy_build_and_compile.sh
cd ..