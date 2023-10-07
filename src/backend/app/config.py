from pydantic_settings import BaseSettings
from dotenv import load_dotenv


class Settings(BaseSettings):
    app_name: str
    db_name: str
    db_user: str
    db_pass: str
    db_host: str

    load_dotenv()
