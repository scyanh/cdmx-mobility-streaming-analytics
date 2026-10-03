# Ships the mobility_pipeline package to Dataflow workers (--setup_file); Beam itself comes
# from the worker container.
import setuptools

setuptools.setup(
    name="mobility-pipeline",
    version="1.0.0",
    packages=setuptools.find_packages(include=["mobility_pipeline", "mobility_pipeline.*"]),
    python_requires=">=3.12",
)
