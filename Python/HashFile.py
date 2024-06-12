import hashlib
class HashFile:
    def __init__(self,path_passed):
        self.filepath = path_passed

    def md5(self):
        hash_md5 = hashlib.md5()
        with open(self.filepath, "rb") as f:
            for chunk in iter(lambda: f.read(4096), b""):
                hash_md5.update(chunk)
        return hash_md5.hexdigest()

    def sha256(self):
        hash_sha256  = hashlib.sha256()
        bytearr  = bytearray(128*1024)
        memview = memoryview(bytearr)
        with open(self.filepath, 'rb', buffering=0) as file:
            for n in iter(lambda : file.readinto(memview), 0):
                hash_sha256.update(memview[:n])
        return hash_sha256.hexdigest()

    def filesize(self):
        st = os.stat(self.filepath)
        return st.st_size

    def all(self) -> list:
        return [ self.md5(), self.sha256(), self.filesize(), self.filepath]
